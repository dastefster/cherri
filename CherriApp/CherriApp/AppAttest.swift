// ===================================
// App Attest Client
// v0.0.1 BUILD 2026-11-09 21:36
// Proves to the signing server that an Export request comes from a genuine copy of this app on a real Apple device. Registers the device once, then signs each request. If anything goes wrong it quietly sends the request without proof, because the server is still in log-only mode.
// dev by @dastefster 🍒🔨
// ===================================

import CryptoKit
import DeviceCheck
import Foundation

// ===================================
// CLIENT
// ===================================

// An actor, so two Exports at once can never register the device twice or tangle the challenge and signature of one request with another.
actor AppAttest {
    static let shared = AppAttest()

    private let service = DCAppAttestService.shared
    private let defaults = UserDefaults.standard

    // The key itself lives in the Secure Enclave and can't be read out. This is only its name, which is not a secret.
    private let keyIdDefaultsKey = "appAttestKeyId"

    // After a failure, trying again right away would only repeat it and spend Apple's rate limit, so wait a while.
    private let retryCooldown: TimeInterval = 10 * 60
    private var lastFailure: Date?

    // Extra headers that prove where a request came from, or none at all when proof isn't possible. Never throws, because Export must keep working without it.
    func headers(for body: Data) async -> [String: String] {
        guard service.isSupported else { return [:] }
        if let lastFailure, Date().timeIntervalSince(lastFailure) < retryCooldown { return [:] }

        do {
            let keyId = try await registeredKey()
            let challenge = try await fetchChallenge()

            // The signature covers the challenge and the request body together, so it can't be reused for anything else.
            let clientData = challenge + Data(SHA256.hash(data: body))
            let assertion = try await service.generateAssertion(keyId, clientDataHash: Data(SHA256.hash(data: clientData)))

            return [
                "X-Attest-Key": keyId,
                "X-Attest-Assertion": assertion.base64EncodedString(),
                "X-Attest-Challenge": challenge.base64EncodedString()
            ]
        } catch {
            fail(error)
            return [:]
        }
    }

    // ===================================
    // REGISTRATION
    // ===================================

    // The saved key if the server already accepted it, otherwise a brand new key that is attested and registered now. A key can only be attested once, so a key that never finished registering is thrown away instead of retried.
    private func registeredKey() async throws -> String {
        if let saved = defaults.string(forKey: keyIdDefaultsKey) { return saved }

        let keyId = try await service.generateKey()
        let challenge = try await fetchChallenge()
        let attestation = try await service.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: challenge)))
        try await register(keyId: keyId, attestation: attestation, challenge: challenge)

        // Only remembered once the server has said yes.
        defaults.set(keyId, forKey: keyIdDefaultsKey)
        return keyId
    }

    private func register(keyId: String, attestation: Data, challenge: Data) async throws {
        var request = makeRequest(path: "attest", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "keyId": keyId,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge.base64EncodedString()
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppAttestError.rejected }
    }

    // ===================================
    // SERVER
    // ===================================

    private func fetchChallenge() async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: makeRequest(path: "challenge", method: "GET"))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encoded = object["challenge"] as? String,
              let challenge = Data(base64Encoded: encoded) else { throw AppAttestError.unavailable }
        return challenge
    }

    // Short timeouts, because proof is a bonus and must never hold up an Export.
    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: ShortcutSigner.server.appendingPathComponent(path), timeoutInterval: 10)
        request.httpMethod = method
        request.setValue(ShortcutSigner.userAgent(detail: "attest"), forHTTPHeaderField: "User-Agent")
        return request
    }

    // ===================================
    // FAILURES
    // ===================================

    private func fail(_ error: Error) {
        lastFailure = Date()

        // Apple says this key is no good any more (the app was restored to another device, say), so start over with a new one next time.
        if (error as? DCError)?.code == .invalidKey {
            defaults.removeObject(forKey: keyIdDefaultsKey)
        }

        #if DEBUG
        print("App Attest unavailable, sending the request without proof: \(error)")
        #endif
    }
}

// ===================================
// ERRORS
// ===================================

private enum AppAttestError: Error {
    case unavailable
    case rejected
}
