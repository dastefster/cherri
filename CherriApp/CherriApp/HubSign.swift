// ===================================
// HubSign Client
// v0.0.5 BUILD 2026-10-25 06:05
// Sends a compiled (unsigned) Shortcut plist to RoutineHub's HubSign service and returns the signed .shortcut bytes.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation

// ===================================
// ERRORS
// ===================================

enum HubSignError: LocalizedError {
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
            return "Could not reach HubSign: \(message)"
        case .timedOut:
            return "HubSign did not answer within 60 seconds. The service may be busy or briefly down. Wait a minute and tap Export again. Your code is safe. If it keeps happening, tap Send Feedback about this error."
        case .badStatus(let code, let detail):
            let suffix = detail.map { " Server said: \($0)" } ?? ""
            switch code {
            case 429:
                return "HubSign is limiting requests right now (HTTP 429). Wait a minute and try Export again.\(suffix)"
            case 500...599:
                return "HubSign had a problem on its end (HTTP \(code)) and the app already retried. Wait a moment and try Export again. If it keeps happening, tap Send Feedback in Settings.\(suffix)"
            default:
                return "HubSign refused to sign the Shortcut (HTTP \(code)).\(suffix)"
            }
        case .badContentType(let type):
            return "HubSign sent back an unexpected response type: \(type)"
        case .notAShortcut:
            return "HubSign's response does not look like a signed Shortcut file."
        }
    }
}

// ===================================
// CLIENT
// ===================================

enum HubSign {
    static let endpoint = URL(string: "https://hubsign.routinehub.services/sign")!

    // Same three types the Cherri command line accepts from this service.
    private static let allowedTypes = ["application/octet-stream", "application/x-plist", "application/x-apple-shortcut"]

    // Signed Shortcuts are AEA archives, which always begin with these four bytes.
    private static let signedMagic = Array("AEA1".utf8)

    static func sign(plist: Data, name: String, compilerVersion: String) async throws -> Data {
        guard let xml = String(data: plist, encoding: .utf8) else {
            throw HubSignError.notText
        }

        // Increased timeout to 60 seconds to accommodate server latency or network drops
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CherriApp/0.0.2 (cherri/\(compilerVersion))", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "shortcutName": name,
            "shortcut": xml
        ])

        // HubSign is a free community service and its 500s come in bursts that can last a minute (a tiny shortcut
        // failed twice in a row while a big one went through right after), so a server error or a rate limit gets
        // four retries spread over about 20 seconds before the user sees a failure. Client errors and timeouts are
        // not retried.
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
                if (error as? URLError)?.code == .timedOut { throw HubSignError.timedOut }
                throw HubSignError.network(error.localizedDescription)
            }

            guard let http = result.1 as? HTTPURLResponse else {
                throw HubSignError.network("No response from the server.")
            }
            if http.statusCode == 200 { break }

            if attempt < maxAttempts, http.statusCode == 429 || http.statusCode >= 500 {
                try await pause(attempt: attempt, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
                attempt += 1
                continue
            }
            throw HubSignError.badStatus(http.statusCode, diagnostics(http, body: result.0, attempt: attempt, since: started))
        }

        guard let http = result.1 as? HTTPURLResponse else {
            throw HubSignError.network("No response from the server.")
        }

        // The header can carry extras like "; charset=binary", so compare only the type itself.
        let rawType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let type = rawType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        guard allowedTypes.contains(type) else {
            throw HubSignError.badContentType(rawType.isEmpty ? "none" : rawType)
        }

        guard result.0.starts(with: signedMagic) else {
            throw HubSignError.notAShortcut
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

    // What the server said plus how the request went, so a failure someone reports can be traced on HubSign's side.
    // The Cloudflare ray ID identifies this exact request.
    private static func diagnostics(_ http: HTTPURLResponse, body: Data, attempt: Int, since started: Date) -> String {
        var parts = [bodySnippet(body) ?? "no message"]
        parts.append("try \(attempt), \(Int(Date().timeIntervalSince(started))) s")
        if let ray = http.value(forHTTPHeaderField: "cf-ray") { parts.append("ray \(ray)") }
        return parts.joined(separator: " · ")
    }

    // A short plain-text reason from the server, if it sent one. HTML error pages are skipped.
    private static func bodySnippet(_ data: Data) -> String? {
        guard let text = String(data: data.prefix(300), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.contains("<") else { return nil }
        return text
    }
}

