import Foundation
import Testing
@testable import CarrierCore

private struct NoInput: Error, LocalizedError { var errorDescription: String? { "No microphone is available: this Mac has no audio input." } }

@MainActor @Test func aCaptureWithNoInputDeviceShowsItsCauseAndLogsOneLineWithoutAudioOrText() async throws {
    let folder = NSTemporaryDirectory() + "carrier-dictation-log-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let log = DictationLog(carrierFolder: folder)
    let session = DictationSession(capture: ScriptedCapture(startError: NoInput()), log: { log.append($0) })
    var text = "mi mensaje"
    let recognizer = ScriptedRecognizer()
    session.start(
        recognizer: recognizer, model: recognizer.models[0],
        into: DictationField(owner: "box", text: { text }, caret: { text.count }, put: { text = $0; _ = ($1, $2) })
    )
    for _ in 0..<3000 where session.state != .idle || session.failure(for: "box") == nil { try await Task.sleep(for: .milliseconds(1)) }
    #expect(session.failure(for: "box")?.cause == "No microphone is available: this Mac has no audio input.")
    #expect(log.path == folder + "/app/logs/dictation.log")
    let lines = try String(contentsOfFile: log.path, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 1)
    #expect(lines[0].hasSuffix("No microphone is available: this Mac has no audio input."))
    #expect(lines[0].contains("mi mensaje") == false)
}

@Test func theLogKeepsAppendingAndAMultilineCauseStaysOnOneLine() throws {
    let folder = NSTemporaryDirectory() + "carrier-dictation-log-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let log = DictationLog(carrierFolder: folder)
    log.append(DictationFailure("first"))
    log.append(DictationFailure("second\nline"))
    #expect(try String(contentsOfFile: log.path, encoding: .utf8).split(separator: "\n").count == 2)
}

@Test func theHomeFolderIsWrittenAsATildeAndTheFileIsCappedWithOneBackup() throws {
    let folder = NSTemporaryDirectory() + "carrier-dictation-log-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let log = DictationLog(carrierFolder: folder, home: "/Users/someone", limit: 200)
    log.append(DictationFailure("Tiny could not be loaded from /Users/someone/.carrier/app/models/whisper/tiny (missing)"))
    var text = try String(contentsOfFile: log.path, encoding: .utf8)
    #expect(text.contains("someone") == false)
    #expect(text.contains("~/.carrier/app/models/whisper/tiny"))

    for number in 0..<10 { log.append(DictationFailure("failure number \(number) with some more words to fill the file up")) }
    text = try String(contentsOfFile: log.path, encoding: .utf8)
    let backup = try String(contentsOfFile: log.path + ".1", encoding: .utf8)
    #expect(text.utf8.count < 400)
    #expect(backup.utf8.count >= 200)
    #expect(text.contains("failure number 9"))
    #expect(FileManager.default.fileExists(atPath: log.path + ".2") == false)
}
