// ===================================
// Mac Pairing
// v0.0.3 BUILD 2026-11-21 10:15
// Pairing with the Cherri Helper on the user's Mac: the saved pairing, the pairing link from the Mac's QR code, and the encrypted (TLS-PSK) client that reaches the Mac by its address from the QR code, or by its Bonjour name, and asks it to sign.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation
import Network
import Security


// ===================================
// PAIRING AND LINK
// ===================================

struct MacPairing {
    let secret: Data
    let serviceName: String
    var hostName: String? = nil
    var port: UInt16? = nil
}

// The Mac shows cherri-pair://v1?k=<secret, base64url>&n=<Bonjour name>&h=<host name>&p=<port> as a QR code.
enum PairingLink {
    static func parse(_ text: String) -> MacPairing? {
        guard
            let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme == "cherri-pair",
            components.host == "v1",
            let key = value("k", in: components),
            let name = value("n", in: components), !name.isEmpty,
            let secret = decodeBase64URL(key), secret.count == 32
        else { return nil }

        // The host and port are optional. Without them the app finds the Mac by its Bonjour name alone.
        var host = value("h", in: components)
        if let candidate = host, candidate.isEmpty || !candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) { host = nil }
        let port = value("p", in: components).flatMap { UInt16($0) }.flatMap { $0 > 0 ? $0 : nil }

        return MacPairing(secret: secret, serviceName: name, hostName: host, port: port)
    }

    private static func value(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }

    private static func decodeBase64URL(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        return Data(base64Encoded: value)
    }
}


// ===================================
// SAVED PAIRING
// ===================================

// The secret lives in the Keychain. The Mac's name, host and port are not secret, so they sit in UserDefaults where the Signing screen can show them.
enum MacPairingStore {
    static let nameKey = "macSignerName"
    private static let hostKey = "macSignerHost"
    private static let portKey = "macSignerPort"
    private static let service = "com.dastefster.CherriApp.macSigner"
    private static let account = "pairing-secret"

    static func load() -> MacPairing? {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: nameKey), !name.isEmpty else { return nil }
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let secret = item as? Data, secret.count == 32 else { return nil }

        let port = defaults.integer(forKey: portKey)
        return MacPairing(secret: secret, serviceName: name, hostName: defaults.string(forKey: hostKey), port: port > 0 ? UInt16(port) : nil)
    }

    static func save(_ pairing: MacPairing) {
        SecItemDelete(baseQuery() as CFDictionary)
        var attributes = baseQuery()
        attributes[kSecValueData as String] = pairing.secret
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)

        let defaults = UserDefaults.standard
        defaults.set(pairing.serviceName, forKey: nameKey)
        defaults.set(pairing.hostName, forKey: hostKey)
        defaults.set(Int(pairing.port ?? 0), forKey: portKey)
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: hostKey)
        defaults.removeObject(forKey: portKey)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}


// ===================================
// ERRORS AND REPLY
// ===================================

enum MacSignerError: Error {
    case notPaired
    case permissionDenied
    case unreachable
    case pairingRejected
    case badReply
    case server(Int, String?)
}

struct MacSignerReply {
    let status: Int
    let body: Data
}


// ===================================
// CLIENT
// ===================================

enum MacSignerClient {
    static let serviceType = "_cherri-signer._tcp"

    // Test hooks for the harness. Nothing sets them in the app.
    nonisolated(unsafe) static var trace: ((String) -> Void)?
    nonisolated(unsafe) static var endpointOverride: NWEndpoint?

    // Asks the helper for its version. Succeeds only when the pairing secret matches, because the TLS handshake itself fails otherwise.
    static func health(pairing: MacPairing) async throws -> String {
        let reply = try await request(method: "GET", path: "/health", body: nil, pairing: pairing, timeout: 20)
        guard
            reply.status == 200,
            let json = try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any],
            json["name"] as? String == "Cherri Helper"
        else { throw MacSignerError.badReply }
        return json["version"] as? String ?? "?"
    }

    // Sends the compiled shortcut and returns the signed bytes. One quiet retry covers a Mac that was asleep or a busy helper.
    static func sign(xml: String, name: String, pairing: MacPairing, onRetry: (() async -> Void)? = nil) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: ["shortcutName": name, "shortcut": xml])
        var attempt = 1

        while true {
            do {
                let reply = try await request(method: "POST", path: "/sign", body: body, pairing: pairing, timeout: 60)
                switch reply.status {
                case 200:
                    guard reply.body.starts(with: Array("AEA1".utf8)) else { throw MacSignerError.badReply }
                    return reply.body
                case 503 where attempt < 2:
                    await onRetry?()
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                    attempt += 1
                    continue
                default:
                    throw MacSignerError.server(reply.status, snippet(reply.body))
                }
            } catch MacSignerError.unreachable where attempt < 2 {
                await onRetry?()
                try await Task.sleep(nanoseconds: 2_000_000_000)
                attempt += 1
            }
        }
    }

    // The Mac's reason, if it sent a short plain-text one.
    private static func snippet(_ data: Data) -> String? {
        guard let text = String(data: data.prefix(300), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.contains("<") else { return nil }
        return text
    }

    // Tries the address from the QR code first, because a host name on the local network is the path that is known to work, then the Bonjour name,
    // which still finds the Mac if its port or host name changed. A real answer from the helper, whatever its status, ends the search.
    static func request(method: String, path: String, body: Data?, pairing: MacPairing, timeout: TimeInterval) async throws -> MacSignerReply {
        var endpoints: [NWEndpoint] = []
        if let override = endpointOverride {
            endpoints = [override]
        } else {
            if let host = pairing.hostName, let port = pairing.port, let nwPort = NWEndpoint.Port(rawValue: port) {
                endpoints.append(.hostPort(host: NWEndpoint.Host(host), port: nwPort))
            }
            endpoints.append(.service(name: pairing.serviceName, type: serviceType, domain: "local", interface: nil))
        }

        var worst: MacSignerError = .unreachable
        for endpoint in endpoints {
            do {
                return try await exchange(on: endpoint, method: method, path: path, body: body, pairing: pairing, timeout: timeout)
            } catch let error as MacSignerError {
                // Keep the most useful reason to show if every address fails.
                switch (worst, error) {
                case (.pairingRejected, _): break
                case (_, .pairingRejected): worst = error
                case (.permissionDenied, _): break
                default: worst = error
                }
                trace?("endpoint \(endpoint) failed: \(error)")
            }
        }
        throw worst
    }

    private static func exchange(on endpoint: NWEndpoint, method: String, path: String, body: Data?, pairing: MacPairing, timeout: TimeInterval) async throws -> MacSignerReply {
        try await withCheckedThrowingContinuation { continuation in
            Exchange(endpoint: endpoint, method: method, path: path, body: body, pairing: pairing, continuation: continuation).start(connectTimeout: 8, requestTimeout: timeout)
        }
    }

    // The pairing secret is the TLS key, so a Mac without the same secret cannot complete the handshake.
    static func parameters(secret: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let key = secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("cherri-helper".utf8).withUnsafeBytes { DispatchData(bytes: $0) }

        sec_protocol_options_add_pre_shared_key(options, key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_set_tls_pre_shared_key_identity_hint(options, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)

        // A resumed session skips the key check, so a stale pairing could keep working after the Mac resets it.
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        sec_protocol_options_set_tls_tickets_enabled(options, false)

        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
}


// ===================================
// ONE REQUEST OVER ONE CONNECTION
// ===================================

private final class Exchange {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.dastefster.CherriApp.macSigner")
    private let requestData: Data
    private let continuation: CheckedContinuation<MacSignerReply, Error>
    private var buffer = Data()
    private var settled = false
    private var permissionPending = false

    init(endpoint: NWEndpoint, method: String, path: String, body: Data?, pairing: MacPairing, continuation: CheckedContinuation<MacSignerReply, Error>) {
        connection = NWConnection(to: endpoint, using: MacSignerClient.parameters(secret: pairing.secret))
        self.continuation = continuation

        var head = "\(method) \(path) HTTP/1.1\r\n"
        head += "Host: cherri-helper.local\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body?.count ?? 0)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        if let body { data.append(body) }
        requestData = data
    }

    // The connect timer covers finding the Mac and finishing the handshake. The request timer starts once the connection is up.
    func start(connectTimeout: TimeInterval, requestTimeout: TimeInterval) {
        connection.stateUpdateHandler = { [self] state in
            MacSignerClient.trace?("state \(state)")
            switch state {
            case .ready:
                send()
                queue.asyncAfter(deadline: .now() + requestTimeout) { [self] in settle(.failure(MacSignerError.unreachable)) }
            case .waiting(let error), .failed(let error):
                handle(error)
            default:
                break
            }
        }
        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + connectTimeout) { [self] in
            guard !connected else { return }
            settle(.failure(permissionPending ? MacSignerError.permissionDenied : MacSignerError.unreachable))
        }
    }

    private var connected = false

    // A failed handshake means the secrets differ. The Local Network prompt shows up as a policy error that clears by itself
    // once the person taps Allow, so that one is waited out instead of treated as final.
    private func handle(_ error: NWError) {
        switch error {
        case .tls:
            settle(.failure(MacSignerError.pairingRejected))
        case .dns(let code) where code == -65570:
            permissionPending = true
        default:
            settle(.failure(MacSignerError.unreachable))
        }
    }

    private func send() {
        connected = true
        permissionPending = false
        connection.send(content: requestData, completion: .contentProcessed { [self] error in
            if error != nil { settle(.failure(MacSignerError.unreachable)) }
        })
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [self] data, _, isComplete, error in
            if let data { buffer.append(data) }
            if isComplete || error != nil { parse() } else { receive() }
        }
    }

    private func parse() {
        guard
            let end = buffer.range(of: Data([13, 10, 13, 10])),
            let head = String(data: buffer[..<end.lowerBound], encoding: .utf8),
            let first = head.components(separatedBy: "\r\n").first,
            case let parts = first.split(separator: " "), parts.count >= 2,
            let status = Int(parts[1])
        else {
            settle(.failure(MacSignerError.badReply))
            return
        }
        settle(.success(MacSignerReply(status: status, body: Data(buffer[end.upperBound...]))))
    }

    private func settle(_ result: Result<MacSignerReply, Error>) {
        guard !settled else { return }
        settled = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(with: result)
    }
}
