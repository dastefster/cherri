// ===================================
// Shortcut Signer Client
// v0.0.12 BUILD 2026-11-21 04:00
// Sends a compiled (unsigned) Shortcut plist to the custom signing server and returns the signed .shortcut bytes. Signs on the user's own Mac instead when My Mac is chosen in Settings (see LocalSigner).
// dev by @dastefster 🍒🔨
// ===================================

import Foundation

// ===================================
// ERRORS
// ===================================

enum ShortcutSignerError: LocalizedError {
    case notText
    case offline
    case unavailable
    case network(String)
    case badStatus(Int, String?)
    case badContentType(String)
    case notAShortcut
    case macNotSet
    case macUnreachable
    case macCodeRejected

    var errorDescription: String? {
        switch self {
        case .notText:
            return "The compiled Shortcut was not valid text, so it could not be sent for signing."
        case .network(let message):
            return "Could not reach the signing server: \(message) The server may be offline. Your code is safe. Try Export again in a minute."
        case .offline:
            return "Your device looks offline, so the Shortcut could not be sent for signing. Check your connection and tap Export again. Your code is safe."
        case .unavailable:
            return "Signing is temporarily unavailable. The signing service can't be reached right now, and it's not a problem with your code. Your code is safe. Try Export again in a little while."
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
        case .macNotSet:
            return "Signing is set to My Mac, but the Mac isn't set up yet. Open Settings, then Signing, and enter its address and pairing code. Your code is safe."
        case .macUnreachable:
            return "Could not reach your Mac. Make sure the Cherri helper is running on it, that this phone is on the same Wi-Fi network, and that Local Network is on for Cherri Shortcuts in the Settings app. Your code is safe."
        case .macCodeRejected:
            return "Your Mac didn't accept the pairing code. Check it in Settings, then Signing, against the one the helper shows. Your code is safe."
        }
    }
}

// ===================================
// CLIENT
// ===================================

enum ShortcutSigner {
    // The signing server is a small service on the developer's Mac, reached through a Tailscale Funnel address.
    // The address stays the same across restarts, so changing it means shipping a new build.
    static let server = URL(string: "https://macbook-pro.tail9f62f6.ts.net")!
    static let endpoint = server.appendingPathComponent("sign")

    // The server turns away anything that doesn't start with "CherriApp/", and the detail in brackets only helps tell requests apart in its log.
    static func userAgent(detail: String) -> String {
        "CherriApp/0.0.2 (\(detail))"
    }

    // The server answers with raw bytes, so this is the type it sends. The other two stay accepted in case that changes.
    private static let allowedTypes = ["application/octet-stream", "application/x-plist", "application/x-apple-shortcut"]

    // Signed Shortcuts are AEA archives, which always begin with these four bytes.
    private static let signedMagic = Array("AEA1".utf8)

    // onRetry lets the caller show what is happening, because a retry after a failed connection can take several seconds and a frozen "Signing…" looks stuck.
    static func sign(plist: Data, name: String, compilerVersion: String, onRetry: (@MainActor (String) -> Void)? = nil) async throws -> Data {
        guard let xml = String(data: plist, encoding: .utf8) else {
            throw ShortcutSignerError.notText
        }

        // When signing is set to the user's own Mac, nothing may fall back to the developer's server, even if the Mac isn't ready, because that would send the shortcut somewhere the user chose not to.
        let usesMac = LocalSigner.usesMac
        let target: URL
        if usesMac {
            guard let macEndpoint = LocalSigner.endpoint, !LocalSigner.pairingCode.isEmpty else {
                throw ShortcutSignerError.macNotSet
            }
            target = macEndpoint
        } else {
            target = endpoint
        }

        // Signing takes a few seconds, and a cold start can take longer, so 60 seconds leaves room.
        var request = URLRequest(url: target, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent(detail: "cherri/\(compilerVersion)"), forHTTPHeaderField: "User-Agent")
        if usesMac {
            request.setValue(LocalSigner.pairingCode, forHTTPHeaderField: "X-Cherri-Pair")
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "shortcutName": name,
            "shortcut": xml
        ])
        request.httpBody = body

        // Server errors, a busy server and rate limits get four retries spread over about 20 seconds before the user
        // sees a failure, because a single sign occasionally fails and then works on the next try. Client errors and
        // timeouts are not retried. A connection that gets cut twice in a row gets one retry only: with the Mac offline
        // the tunnel resets every request, and five rounds of that kept the user waiting about a minute.
        let maxAttempts = 5
        var attempt = 1
        var droppedConnections = 0
        var result: (Data, URLResponse)
        let started = Date()

        while true {
            // Each attempt needs its own proof, because a challenge works only once. This never fails, it just comes back empty when proof isn't possible.
            // The Mac helper checks the pairing code instead, so App Attest is only for the developer's server.
            var attemptRequest = request
            if !usesMac {
                for (header, value) in await AppAttest.shared.headers(for: body) {
                    attemptRequest.setValue(value, forHTTPHeaderField: header)
                }
            }

            do {
                result = try await URLSession.shared.data(for: attemptRequest)
                droppedConnections = 0
            } catch {
                if isRetryable(error) { droppedConnections += 1 }
                if attempt < maxAttempts, droppedConnections < 2, isRetryable(error) {
                    await onRetry?("Having trouble reaching the signing server, trying again…")
                    try await pause(attempt: attempt)
                    attempt += 1
                    continue
                }
                if usesMac, error is URLError { throw ShortcutSignerError.macUnreachable }
                if let urlError = error as? URLError {
                    if offlineCodes.contains(urlError.code) { throw ShortcutSignerError.offline }
                    if unreachableCodes.contains(urlError.code) { throw ShortcutSignerError.unavailable }
                }
                throw ShortcutSignerError.network(error.localizedDescription)
            }

            guard let http = result.1 as? HTTPURLResponse else {
                throw ShortcutSignerError.network("No response from the server.")
            }
            if http.statusCode == 200 { break }

            if attempt < maxAttempts, http.statusCode == 429 || http.statusCode >= 500 {
                await onRetry?("The signing server is busy, trying again…")
                try await pause(attempt: attempt, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
                attempt += 1
                continue
            }
            // The signer's own 502 carries a plain-text reason. A 502 or 504 with none came from the tunnel, which means the signer is not answering.
            if usesMac, http.statusCode == 401 { throw ShortcutSignerError.macCodeRejected }
            if http.statusCode == 502 || http.statusCode == 504, bodySnippet(result.0) == nil {
                throw usesMac ? ShortcutSignerError.macUnreachable : ShortcutSignerError.unavailable
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

    // The phone itself has no usable connection.
    private static let offlineCodes: Set<URLError.Code> = [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff]

    // The phone is online but the signer never answered. The Mac may be asleep, offline or restarting.
    private static let unreachableCodes: Set<URLError.Code> = [.timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost, .secureConnectionFailed]

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
