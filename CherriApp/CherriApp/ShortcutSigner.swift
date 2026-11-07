// ===================================
// Shortcut Signer Client
// v0.0.6 BUILD 2026-11-06 22:10
// Sends a compiled (unsigned) Shortcut plist to the Cherri Shortcuts signing server and returns the signed .shortcut bytes.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation

// ===================================
// ERRORS
// ===================================

enum ShortcutSignerError: LocalizedError {
    case notText
    case network(String)
    case timedOut
    case badStatus(Int, String?)
    case badContentType(String)
    case notAShortcut

    var errorDescription: String? {
        switch self {
        case .notText:
            return "The compiled Shortcut was not valid text, so it could not be sent for signing."
        case .network(let message):
            return "Could not reach the signing server: \(message) The server may be offline. Your code is safe. Try Export again in a minute."
        case .timedOut:
            return "The signing server did not answer within 60 seconds. It may be busy or offline. Wait a minute and tap Export again. Your code is safe. If it keeps happening, tap Send Feedback about this error."
        case .badStatus(let code, let detail):
            let suffix = detail.map { " Server said: \($0)" } ?? ""
            switch code {
            case 429:
                return "The signing server is limiting requests right now (HTTP 429). Wait a minute and try Export again.\(suffix)"
            case 503:
                return "The signing server is busy right now (HTTP 503) and the app already retried. Wait a moment and try Export again.\(suffix)"
            case 500...599:
                return "The signing server had a problem (HTTP \(code)) and the app already retried. It may be offline. Wait a moment and try Export again. If it keeps happening, tap Send Feedback in Settings.\(suffix)"
            default:
                return "The signing server refused to sign the Shortcut (HTTP \(code)).\(suffix)"
            }
        case .badContentType(let type):
            return "The signing server sent back an unexpected response type: \(type)"
        case .notAShortcut:
            return "The signing server's response does not look like a signed Shortcut file."
        }
    }
}

// ===================================
// CLIENT
// ===================================

enum ShortcutSigner {
    // The signing server is a small service on the developer's Mac, reached through a Tailscale Funnel address.
    // The address stays the same across restarts, so changing it means shipping a new build.
    static let endpoint = URL(string: "https://macbook-pro.tail9f62f6.ts.net/sign")!

    // The server answers with raw bytes, so this is the type it sends. The other two stay accepted in case that changes.
    private static let allowedTypes = ["application/octet-stream", "application/x-plist", "application/x-apple-shortcut"]

    // Signed Shortcuts are AEA archives, which always begin with these four bytes.
    private static let signedMagic = Array("AEA1".utf8)

    static func sign(plist: Data, name: String, compilerVersion: String) async throws -> Data {
        guard let xml = String(data: plist, encoding: .utf8) else {
            throw ShortcutSignerError.notText
        }

        // Signing takes a few seconds, and a cold start can take longer, so 60 seconds leaves room.
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CherriApp/0.0.2 (cherri/\(compilerVersion))", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "shortcutName": name,
            "shortcut": xml
        ])

        // Server errors, a busy server and rate limits get four retries spread over about 20 seconds before the user
        // sees a failure, because a single sign occasionally fails and then works on the next try. Client errors and
        // timeouts are not retried.
        let maxAttempts = 5
        var attempt = 1
        var result: (Data, URLResponse)
        let started = Date()

        while true {
            do {
                result = try await URLSession.shared.data(for: request)
            } catch {
                if attempt < maxAttempts, isRetryable(error) {
                    try await pause(attempt: attempt)
                    attempt += 1
                    continue
                }
                if (error as? URLError)?.code == .timedOut { throw ShortcutSignerError.timedOut }
                throw ShortcutSignerError.network(error.localizedDescription)
            }

            guard let http = result.1 as? HTTPURLResponse else {
                throw ShortcutSignerError.network("No response from the server.")
            }
            if http.statusCode == 200 { break }

            if attempt < maxAttempts, http.statusCode == 429 || http.statusCode >= 500 {
                try await pause(attempt: attempt, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
                attempt += 1
                continue
            }
            throw ShortcutSignerError.badStatus(http.statusCode, diagnostics(body: result.0, attempt: attempt, since: started))
        }

        guard let http = result.1 as? HTTPURLResponse else {
            throw ShortcutSignerError.network("No response from the server.")
        }

        // The header can carry extras like "; charset=binary", so compare only the type itself.
        let rawType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let type = rawType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        guard allowedTypes.contains(type) else {
            throw ShortcutSignerError.badContentType(rawType.isEmpty ? "none" : rawType)
        }

        guard result.0.starts(with: signedMagic) else {
            throw ShortcutSignerError.notAShortcut
        }

        return result.0
    }

    // A dropped connection is worth another try. A timeout already cost 60 seconds, so it is not.
    private static func isRetryable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .networkConnectionLost || urlError.code == .cannotConnectToHost
    }

    // Honors a Retry-After value given in seconds, but never makes the user wait long. Waits 2, 4, 6, 8 seconds.
    private static func pause(attempt: Int, retryAfter: String? = nil) async throws {
        let requested = retryAfter.flatMap { Double($0) } ?? 0
        let seconds = min(max(requested, Double(attempt) * 2), 8)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // What the server said plus how the request went, so a failure someone reports can be matched to the server log.
    private static func diagnostics(body: Data, attempt: Int, since started: Date) -> String {
        let parts = [bodySnippet(body) ?? "no message", "try \(attempt), \(Int(Date().timeIntervalSince(started))) s"]
        return parts.joined(separator: " · ")
    }

    // A short plain-text reason from the server, if it sent one. HTML error pages are skipped.
    private static func bodySnippet(_ data: Data) -> String? {
        guard let text = String(data: data.prefix(300), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.contains("<") else { return nil }
        return text
    }
}
