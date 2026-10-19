// ===================================
// HubSign Client
// v0.0.1 BUILD 2026-10-15 13:40
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
    case badStatus(Int)
    case badContentType(String)
    case notAShortcut

    var errorDescription: String? {
        switch self {
        case .notText:
            return "The compiled Shortcut was not valid text, so it could not be sent for signing."
        case .network(let message):
            return "Could not reach HubSign: \(message)"
        case .badStatus(let code):
            return "HubSign refused to sign the Shortcut (HTTP \(code)). It may be rate limiting; try again in a moment."
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

        var result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw HubSignError.network(error.localizedDescription)
        }

        guard let http = result.1 as? HTTPURLResponse else {
            throw HubSignError.network("No response from the server.")
        }
        guard http.statusCode == 200 else {
            throw HubSignError.badStatus(http.statusCode)
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
}

