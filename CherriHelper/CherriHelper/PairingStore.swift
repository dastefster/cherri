// ===================================
// Pairing Store
// v0.0.3 BUILD 2026-11-21@15:45
// Holds the 32-byte pairing secret (the TLS-PSK key) and builds the pairing QR link.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation
import AppKit
import Security


// ===================================
// SECRET STORAGE
// ===================================

// Stored in a 0600 file for now: an ad hoc dev signature changes on every rebuild, which would trigger a Keychain
// prompt each time. Move this to the Keychain once the app is signed with a stable Developer ID identity.
final class PairingStore {
    static let identity = "cherri-helper"

    private(set) var secret: Data
    // True when this run had to create the key, which is how a first launch tells itself apart from an update.
    let isNew: Bool
    private let fileURL: URL

    init() {
        let folder = StoragePaths.supportFolder
        let url = folder.appendingPathComponent("pairing.key")
        fileURL = url

        if let existing = try? Data(contentsOf: url), existing.count == 32 {
            secret = existing
            isNew = false
        } else {
            secret = PairingStore.randomSecret()
            PairingStore.write(secret, to: url)
            isNew = true
        }
    }

    func regenerate() {
        secret = PairingStore.randomSecret()
        PairingStore.write(secret, to: fileURL)
        Log.write("pairing reset")
    }

    // The QR carries the secret, the Bonjour name, and this Mac's host name and port, so the phone can find it without anyone typing an address.
    func pairingURL(serviceName: String, host: String?, port: Int?) -> String {
        var components = URLComponents()
        components.scheme = "cherri-pair"
        components.host = "v1"
        components.queryItems = [
            URLQueryItem(name: "k", value: PairingStore.base64URL(secret)),
            URLQueryItem(name: "n", value: serviceName),
        ]
        // The phone tries this address first and falls back to the Bonjour name, so a changed host or port still works.
        if let host { components.queryItems?.append(URLQueryItem(name: "h", value: host)) }
        if let port { components.queryItems?.append(URLQueryItem(name: "p", value: String(port))) }
        return components.string ?? ""
    }

    private static func randomSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Could not generate a pairing secret")
        return Data(bytes)
    }

    private static func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
