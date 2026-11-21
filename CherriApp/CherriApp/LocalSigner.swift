// ===================================
// Local Signer
// v0.0.1 BUILD 2026-11-21 04:00
// Lets Export sign on the user's own Mac over the local network instead of the developer's signing server. Holds the saved choice (server or Mac, the Mac's address, the pairing code) and the Signing settings screen that edits and tests it.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// SAVED CHOICE
// ===================================

enum LocalSigner {
    static let modeKey = "signingMode"
    static let addressKey = "localSignerAddress"
    static let codeKey = "localSignerCode"
    static let serverMode = "server"
    static let macMode = "mac"

    // The port the Mac helper listens on unless told otherwise.
    static let defaultPort = 8788

    static var usesMac: Bool {
        UserDefaults.standard.string(forKey: modeKey) == macMode
    }

    // Names where Export is sending the shortcut, for the confirmation and footer text.
    static var destination: String {
        usesMac ? "your Mac" : "the custom signing server"
    }

    static var pairingCode: String {
        (UserDefaults.standard.string(forKey: codeKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    // The /sign address on the Mac, or nil when no usable address has been entered.
    static var endpoint: URL? {
        baseURL(from: UserDefaults.standard.string(forKey: addressKey) ?? "")?.appendingPathComponent("sign")
    }

    // Accepts "my-mac.local", "192.168.1.20" or a full "http://my-mac.local:8788", and fills in the port when it is missing.
    static func baseURL(from text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "http://" + value }
        guard var parts = URLComponents(string: value), let host = parts.host, !host.isEmpty else { return nil }
        parts.scheme = "http"
        if parts.port == nil { parts.port = defaultPort }
        parts.path = ""
        parts.query = nil
        return parts.url
    }

    // ===================================
    // CONNECTION TEST
    // ===================================

    // Checks that something answers like the Cherri helper, then that it accepts the pairing code.
    static func testConnection(address: String, code: String) async -> String {
        guard let base = baseURL(from: address) else { return "Enter your Mac's address first." }
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCode.isEmpty else { return "Enter the pairing code the helper shows." }

        do {
            var health = URLRequest(url: base.appendingPathComponent("health"), timeoutInterval: 8)
            health.setValue(ShortcutSigner.userAgent(detail: "test"), forHTTPHeaderField: "User-Agent")
            let (healthData, healthResponse) = try await URLSession.shared.data(for: health)
            let healthStatus = (healthResponse as? HTTPURLResponse)?.statusCode ?? 0
            guard healthStatus == 200,
                  let info = try? JSONSerialization.jsonObject(with: healthData) as? [String: Any],
                  (info["name"] as? String) == "Cherri Local Signer" else {
                return "Something answered, but it isn't the Cherri helper."
            }
            let version = info["version"] as? String ?? "?"

            var pair = URLRequest(url: base.appendingPathComponent("pair"), timeoutInterval: 8)
            pair.setValue(ShortcutSigner.userAgent(detail: "test"), forHTTPHeaderField: "User-Agent")
            pair.setValue(cleanCode, forHTTPHeaderField: "X-Cherri-Pair")
            let (_, pairResponse) = try await URLSession.shared.data(for: pair)
            let pairStatus = (pairResponse as? HTTPURLResponse)?.statusCode ?? 0
            switch pairStatus {
            case 200: return "Connected. Cherri helper \(version) accepted the pairing code."
            case 401: return "Found the helper (\(version)), but it didn't accept that pairing code."
            case 429: return "Too many wrong codes. Wait a minute and try again."
            default: return "Found the helper (\(version)), but pairing failed."
            }
        } catch {
            return "Could not reach that address. Check that the helper is running, that this phone is on the same Wi-Fi, and that Local Network is on for Cherri Shortcuts in the Settings app."
        }
    }
}

// ===================================
// SIGNING SETTINGS SCREEN
// ===================================

struct LocalSignerView: View {
    @AppStorage(LocalSigner.modeKey) private var mode = LocalSigner.serverMode
    @AppStorage(LocalSigner.addressKey) private var address = ""
    @AppStorage(LocalSigner.codeKey) private var code = ""
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        List {
            Section {
                Picker("Sign with", selection: $mode) {
                    Text("Cherri Server").tag(LocalSigner.serverMode)
                    Text("My Mac").tag(LocalSigner.macMode)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(mode == LocalSigner.macMode
                     ? "Exports are signed by the Cherri helper on your own Mac, over your local network. Nothing is sent to the Cherri server. Your Mac still contacts Apple's servers to sign."
                     : "Exports are signed by the custom signing server run by the app's developer.")
                    .foregroundStyle(Color.helperText)
            }

            if mode == LocalSigner.macMode {
                Section {
                    TextField("Mac address, like my-mac.local", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Pairing code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Your Mac")
                } footer: {
                    Text("Run the Cherri helper on your Mac, then enter its address and the pairing code it shows. Your phone and Mac need to be on the same Wi-Fi network. If this is set to My Mac, Export never falls back to the Cherri server.")
                        .foregroundStyle(Color.helperText)
                }

                Section {
                    Button {
                        testing = true
                        testResult = nil
                        Task {
                            testResult = await LocalSigner.testConnection(address: address, code: code)
                            testing = false
                        }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            if testing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(testing)

                    if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(Color.helperText)
                    }
                }
            }
        }
        .navigationTitle("Signing")
        .navigationBarTitleDisplayMode(.inline)
    }
}
