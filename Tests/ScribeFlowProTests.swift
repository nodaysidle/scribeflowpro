import Foundation
import Testing
@testable import ScribeFlowPro

@Test func audioDeviceEnumeration() async throws {
    let actor = AudioCaptureActor()
    let devices = actor.listInputDevices()
    #expect(devices.allSatisfy { !$0.name.isEmpty })
}

@Test func modelPathResolverFindsFlatAndNestedLayouts() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScribeFlowProTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let nested = root
        .appendingPathComponent("mlx-community", isDirectory: true)
        .appendingPathComponent("Llama-3.2-3B-Instruct-4bit", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    #expect(ModelPathResolver.existingDirectory(
        for: "mlx-community/Llama-3.2-3B-Instruct-4bit",
        in: root
    )?.standardizedFileURL.path == nested.standardizedFileURL.path)

    try FileManager.default.removeItem(at: nested.deletingLastPathComponent())
    let flat = ModelPathResolver.storageDirectory(
        for: "mlx-community/Llama-3.2-3B-Instruct-4bit",
        in: root
    )
    try FileManager.default.createDirectory(at: flat, withIntermediateDirectories: true)

    #expect(ModelPathResolver.existingDirectory(
        for: "mlx-community/Llama-3.2-3B-Instruct-4bit",
        in: root
    )?.standardizedFileURL.path == flat.standardizedFileURL.path)
}

@Test func modelPathResolverRoundTripsRepoNames() {
    #expect(ModelPathResolver.flattenedModelID("mlx-community/whisper-medium-mlx") == "mlx-community_whisper-medium-mlx")
    #expect(ModelPathResolver.repoID(
        from: URL(fileURLWithPath: "/tmp/Models/mlx-community_whisper-medium-mlx"),
        orgName: nil
    ) == "mlx-community/whisper-medium-mlx")
    #expect(ModelPathResolver.repoID(
        from: URL(fileURLWithPath: "/tmp/Models/mlx-community/whisper-medium-mlx"),
        orgName: "mlx-community"
    ) == "mlx-community/whisper-medium-mlx")
}

@Test func whisperControlTokensAreStripped() {
    let cleaned = WhisperTranscriptionActor.cleanWhisperText(" <|startoftranscript|><|en|><|transcribe|> Hello world <|0.00|> ")
    #expect(cleaned == "Hello world")
}
