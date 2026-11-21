// ===================================
// Signer
// v0.0.1 BUILD 2026-11-21@10:00
// Runs Apple's `shortcuts sign` in a temp folder that is deleted as soon as signing finishes.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation


// ===================================
// SIGNING
// ===================================

final class Signer {
    enum Failure: LocalizedError {
        case busy
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .busy: return "busy"
            case .failed(let reason): return reason
            }
        }
    }

    private static let signedMagic = Data("AEA1".utf8)
    private static let maxConcurrentSigns = 2
    private static let queueWaitSeconds = 20.0
    private static let signTimeoutSeconds = 45.0

    private let slots = DispatchSemaphore(value: Signer.maxConcurrentSigns)

    func sign(plist: Data) throws -> Data {
        guard slots.wait(timeout: .now() + Self.queueWaitSeconds) == .success else { throw Failure.busy }
        defer { slots.signal() }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("cherri-helper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let input = work.appendingPathComponent("in.shortcut")
        let output = work.appendingPathComponent("out.shortcut")
        try plist.write(to: input)

        // One quiet retry, because an occasional single sign failed during prototype testing and then worked.
        var lastError = "unknown error"
        for _ in 1...2 {
            switch run(input: input, output: output) {
            case .success(let signed):
                return signed
            case .failure(let reason):
                lastError = reason.errorDescription ?? "signing failed"
                try? FileManager.default.removeItem(at: output)
            }
        }
        throw Failure.failed(lastError)
    }

    private func run(input: URL, output: URL) -> Result<Data, Failure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["sign", "--mode", "anyone", "--input", input.path, "--output", output.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do { try process.run() } catch { return .failure(.failed("could not start shortcuts: \(error.localizedDescription)")) }

        if exited.wait(timeout: .now() + Self.signTimeoutSeconds) == .timedOut {
            process.terminate()
            return .failure(.failed("signing timed out"))
        }

        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus == 0, let signed = try? Data(contentsOf: output) {
            if signed.starts(with: Self.signedMagic) { return .success(signed) }
            return .failure(.failed("signer returned an unexpected file"))
        }

        let reason = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? "signing failed"
        return .failure(.failed(String(reason.prefix(200))))
    }
}
