@preconcurrency import AVFoundation
import CoreAudio
import os

/// Thread-safe container for converted audio samples.
struct AudioSamples: Sendable {
    let samples: [Float]
    let frameCount: Int
}

actor AudioCaptureActor {
    static let logger = Logger(subsystem: "com.scribeflowpro", category: "AudioCapture")

    private var engine: AVAudioEngine?
    private var continuation: AsyncStream<AudioSamples>.Continuation?
    private var ringBuffer: [Float] = []
    private let maxRingBufferSamples = 16_000 * 60 // 60 seconds at 16kHz
    private var tempFileWriter: AVAudioFile?
    private var targetFormat: AVAudioFormat?

    private(set) var isCapturing = false
    private(set) var audioFileURL: URL?

    static let targetSampleRate: Double = 16_000
    private static let targetChannelCount: AVAudioChannelCount = 1

    func startCapture(inputDevice: AudioDevice? = nil) throws -> AsyncStream<AudioSamples> {
        Self.logger.info("Starting audio capture")

        guard checkMicrophonePermission() else {
            throw AudioCaptureError.permissionDenied
        }

        let engine = AVAudioEngine()
        self.engine = engine

        if let device = inputDevice {
            setInputDevice(device, on: engine)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannelCount,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatConversionFailed
        }
        self.targetFormat = targetFmt

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFmt) else {
            throw AudioCaptureError.formatConversionFailed
        }

        ringBuffer.removeAll()
        ringBuffer.reserveCapacity(maxRingBufferSamples)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        self.audioFileURL = tempURL
        self.tempFileWriter = try? AVAudioFile(
            forWriting: tempURL,
            settings: targetFmt.settings
        )

        let stream = AsyncStream<AudioSamples>(
            bufferingPolicy: .bufferingNewest(100)
        ) { continuation in
            self.continuation = continuation
        }

        // Capture file writer reference for use in tap (nonisolated context)
        let fileWriter = self.tempFileWriter

        let bufferSize: AVAudioFrameCount = 4800
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self] buffer, _ in
            // All conversion happens on the audio thread — no actor hop for non-Sendable types
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * Self.targetSampleRate / buffer.format.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFmt,
                frameCapacity: frameCapacity + 100
            ) else { return }

            var error: NSError?
            let sourceBuffer = buffer
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return sourceBuffer
            }

            guard error == nil, convertedBuffer.frameLength > 0 else { return }

            // Write to temp file on audio thread (before crossing isolation)
            try? fileWriter?.write(from: convertedBuffer)

            // Extract Sendable data before crossing isolation boundary
            guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(
                start: channelData, count: Int(convertedBuffer.frameLength)
            ))
            let audioSamples = AudioSamples(samples: samples, frameCount: Int(convertedBuffer.frameLength))

            guard let self else { return }
            Task {
                await self.handleConvertedSamples(audioSamples)
            }
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioCaptureError.engineStartFailed(underlying: error)
        }

        isCapturing = true
        Self.logger.info("Audio capture started successfully")
        return stream
    }

    func stopCapture() {
        guard isCapturing else { return }
        Self.logger.info("Stopping audio capture")

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        tempFileWriter = nil
        targetFormat = nil
        continuation?.finish()
        continuation = nil
        ringBuffer.removeAll()

        isCapturing = false
        Self.logger.info("Audio capture stopped")
    }

    nonisolated func listInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let getStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard getStatus == noErr else { return [] }

        let defaultInputID = getDefaultInputDeviceID()

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard hasInputStreams(deviceID: deviceID) else { return nil }
            let name = getDeviceName(deviceID: deviceID) ?? "Unknown"
            let sampleRate = getDeviceSampleRate(deviceID: deviceID)
            return AudioDevice(
                id: String(deviceID),
                name: name,
                sampleRate: sampleRate,
                isDefault: deviceID == defaultInputID
            )
        }
    }

    // MARK: - Private

    private func handleConvertedSamples(_ audioSamples: AudioSamples) {
        ringBuffer.append(contentsOf: audioSamples.samples)
        if ringBuffer.count > maxRingBufferSamples {
            ringBuffer.removeFirst(ringBuffer.count - maxRingBufferSamples)
        }

        continuation?.yield(audioSamples)
    }

    private func checkMicrophonePermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            // Use nonisolated(unsafe) to bridge the synchronous semaphore pattern
            nonisolated(unsafe) var granted = false
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { result in
                granted = result
                semaphore.signal()
            }
            semaphore.wait()
            return granted
        default:
            return false
        }
    }

    private func setInputDevice(_ device: AudioDevice, on engine: AVAudioEngine) {
        guard let deviceID = UInt32(device.id) else { return }
        var deviceIDVar = deviceID
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit!
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDVar,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private nonisolated func getDefaultInputDeviceID() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    private nonisolated func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private nonisolated func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, ptr)
        }
        return status == noErr ? name as String : nil
    }

    private nonisolated func getDeviceSampleRate(deviceID: AudioDeviceID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &sampleRate)
        return sampleRate
    }
}
