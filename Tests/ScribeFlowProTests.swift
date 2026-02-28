import Testing
@testable import ScribeFlowPro

@Test func audioDeviceEnumeration() async throws {
    let actor = AudioCaptureActor()
    let devices = actor.listInputDevices()
    // On CI or machines without audio, this may be empty
    // but the call itself should not crash
    #expect(devices.allSatisfy { !$0.name.isEmpty })
}
