// ===================================
// Helper Server
// v0.0.1 BUILD 2026-11-21@10:00
// Encrypted local HTTP server (TLS-PSK) with GET /health and POST /sign, advertised over Bonjour.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation
import Network
import Security


// ===================================
// SERVER
// ===================================

final class HelperServer {
    static let serviceType = "_cherri-signer._tcp"
    static let version = "0.0.1"
    static let maxBodyBytes = 2 * 1024 * 1024
    static let maxNameLength = 120

    var onStatus: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.dastefster.CherriHelper.server")
    private var listener: NWListener?
    private let signer = Signer()

    func start(secret: Data, serviceName: String) {
        listener?.cancel()
        listener = nil

        do {
            let newListener = try NWListener(using: Self.parameters(secret: secret))
            newListener.service = NWListener.Service(name: serviceName, type: Self.serviceType, txtRecord: NWTXTRecord(["v": "1"]))

            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                switch state {
                case .ready:
                    let port = Int(newListener?.port?.rawValue ?? 0)
                    self?.onStatus?("Ready, listening on port \(port)")
                    StatusFile.write(port: port, serviceName: serviceName)
                    Log.write("listening on port \(port)")
                case .failed(let error):
                    self?.onStatus?("Server failed: \(error.localizedDescription)")
                    Log.write("listener failed: \(error)")
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Exchange(connection: connection, queue: self.queue, signer: self.signer).begin()
            }

            newListener.start(queue: queue)
            listener = newListener
        } catch {
            onStatus?("Could not start: \(error.localizedDescription)")
            Log.write("could not start listener: \(error)")
        }
    }

    // The pairing secret is the TLS key itself, so a Mac or phone without it cannot complete the handshake.
    static func parameters(secret: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let key = secret.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(PairingStore.identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }

        sec_protocol_options_add_pre_shared_key(options, key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_set_tls_pre_shared_key_identity_hint(options, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)

        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
}


// ===================================
// ONE REQUEST, ONE CONNECTION
// ===================================

private final class Exchange {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let signer: Signer
    private var buffer = Data()
    private var finished = false

    init(connection: NWConnection, queue: DispatchQueue, signer: Signer) {
        self.connection = connection
        self.queue = queue
        self.signer = signer
    }

    func begin() {
        connection.stateUpdateHandler = { [self] state in
            if case .failed = state { finish() }
        }
        connection.start(queue: queue)
        receive()

        // Drops anything that stalls instead of finishing its request.
        queue.asyncAfter(deadline: .now() + 20) { [self] in finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty { buffer.append(data) }
            if error != nil { finish(); return }

            switch HTTPRequest.parse(buffer) {
            case .needMore:
                if isComplete { finish() } else { receive() }
            case .invalid(let status, let message):
                respond(status: status, body: Data(message.utf8), type: "text/plain; charset=utf-8")
            case .ready(let request):
                route(request)
            }
        }
    }

    private func route(_ request: HTTPRequest) {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            let body = "{\"ok\": true, \"name\": \"Cherri Helper\", \"version\": \"\(HelperServer.version)\"}"
            respond(status: 200, body: Data(body.utf8), type: "application/json")

        case ("POST", "/sign"):
            let started = Date()
            // Signing blocks for seconds, so it runs off the network queue.
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let outcome = SignRequest.handle(body: request.body, signer: signer, started: started)
                queue.async { [self] in
                    switch outcome {
                    case .signed(let data):
                        respond(status: 200, body: data, type: "application/octet-stream")
                    case .failure(let status, let message, let retryAfter):
                        respond(status: status, body: Data(message.utf8), type: "text/plain; charset=utf-8", retryAfter: retryAfter)
                    }
                }
            }

        default:
            respond(status: 404, body: Data("Not found.".utf8), type: "text/plain; charset=utf-8")
        }
    }

    private func respond(status: Int, body: Data, type: String, retryAfter: Int? = nil) {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        if let retryAfter { head += "Retry-After: \(retryAfter)\r\n" }
        head += "Connection: close\r\n\r\n"

        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [self] _ in
            finish()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        case 431: return "Request Header Fields Too Large"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "Error"
        }
    }
}


// ===================================
// HTTP PARSING
// ===================================

private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    enum Result {
        case needMore
        case invalid(Int, String)
        case ready(HTTPRequest)
    }

    static func parse(_ data: Data) -> Result {
        let separator = Data([13, 10, 13, 10])
        guard let headerEnd = data.range(of: separator) else {
            return data.count > 16 * 1024 ? .invalid(431, "Headers are too large.") : .needMore
        }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid(400, "Bad request.")
        }

        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return .invalid(400, "Bad request.") }

        var contentLength = 0
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1)
            if pieces.count == 2, pieces[0].lowercased() == "content-length" {
                contentLength = Int(pieces[1].trimmingCharacters(in: .whitespaces)) ?? -1
            }
        }
        if contentLength < 0 { return .invalid(400, "Bad request.") }
        if contentLength > HelperServer.maxBodyBytes { return .invalid(413, "Shortcut is too large to sign.") }

        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= contentLength else { return .needMore }

        let body = Data(data[bodyStart..<(bodyStart + contentLength)])
        return .ready(HTTPRequest(method: String(parts[0]), path: String(parts[1]), body: body))
    }
}


// ===================================
// SIGN REQUEST
// ===================================

private enum SignRequest {
    enum Outcome {
        case signed(Data)
        case failure(Int, String, Int?)
    }

    // Same body shape the iOS app already sends: {"shortcutName": "...", "shortcut": "<plist xml>"}.
    static func handle(body: Data, signer: Signer, started: Date) -> Outcome {
        guard body.count > 0 else { return .failure(400, "Missing request body.", nil) }

        guard
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let name = json["shortcutName"] as? String, name.count <= HelperServer.maxNameLength,
            let xml = json["shortcut"] as? String,
            let plist = try? PropertyListSerialization.propertyList(from: Data(xml.utf8), options: [], format: nil) as? [String: Any],
            plist["WFWorkflowActions"] is [Any]
        else {
            Log.write("400 bad request (\(body.count) bytes)")
            return .failure(400, "That does not look like a compiled Shortcut.", nil)
        }

        do {
            let signed = try signer.sign(plist: Data(xml.utf8))
            Log.write(String(format: "200 signed %d bytes in, %d bytes out, %.1fs", xml.utf8.count, signed.count, Date().timeIntervalSince(started)))
            return .signed(signed)
        } catch Signer.Failure.busy {
            Log.write("503 busy")
            return .failure(503, "Signing is busy right now. Try again in a moment.", 10)
        } catch {
            let code = String(format: "%06x", Int.random(in: 0..<0xFFFFFF))
            Log.write("502 sign failed [\(code)]: \(error.localizedDescription)")
            return .failure(502, "Signing failed on this Mac (code \(code)). Make sure it is signed in to iCloud and online.", nil)
        }
    }
}
