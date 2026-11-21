// ===================================
// Local Signer
// v0.0.3 BUILD 2026-11-21 16:58
// Lets Export sign on the user's own Mac instead of the developer's signing server. Holds the saved choice (server or Mac) and the Signing settings screen that downloads the Cherri Helper, pairs with it by QR code and tests the connection.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI


// ===================================
// SAVED CHOICE
// ===================================

enum LocalSigner {
    static let modeKey = "signingMode"
    static let serverMode = "server"
    static let macMode = "mac"

    // GitHub redirects "latest/download" to the newest release's file, so this link never needs updating when the helper does. The release repo holds only helper releases, which keeps "latest" pointing at the helper.
    static let helperDownloadURL = URL(string: "https://github.com/dastefster/cherricuts/releases/latest/download/Cherri-Helper.dmg")!

    static var usesMac: Bool {
        UserDefaults.standard.string(forKey: modeKey) == macMode
    }

    // Names where Export is sending the shortcut, for the confirmation and footer text.
    static var destination: String {
        usesMac ? "your Mac" : "the custom signing server"
    }

    // Plain-words description of why a Mac request failed, shared by the test button and the Export errors.
    static func explain(_ error: Error) -> String {
        guard let error = error as? MacSignerError else { return "Something went wrong talking to your Mac." }
        switch error {
        case .notPaired:
            return "No Mac is paired yet. Scan the QR code on your Mac first."
        case .permissionDenied:
            return "Local Network is off for Cherri Shortcuts. Turn it on in the Settings app, under Privacy & Security, then Local Network."
        case .unreachable:
            return "Could not find your Mac. Check that Cherri Helper is running on it and that this phone is on the same Wi-Fi network."
        case .pairingRejected:
            return "Your Mac didn't accept this pairing. It may have been reset. Scan the QR code on your Mac again."
        case .badReply, .server:
            return "Something answered, but it isn't the Cherri Helper."
        }
    }

    // ===================================
    // CONNECTION TEST
    // ===================================

    static func testConnection() async -> String {
        guard let pairing = MacPairingStore.load() else { return explain(MacSignerError.notPaired) }
        do {
            let version = try await MacSignerClient.health(pairing: pairing)
            return "Connected. Cherri Helper \(version) is ready on \(pairing.serviceName)."
        } catch {
            return explain(error)
        }
    }
}


// ===================================
// SIGNING SETTINGS SCREEN
// ===================================

struct LocalSignerView: View {
    @AppStorage(LocalSigner.modeKey) private var mode = LocalSigner.serverMode
    @AppStorage(MacPairingStore.nameKey) private var macName = ""
    @State private var paired = MacPairingStore.load() != nil
    @State private var showingScanner = false
    @State private var working = false
    @State private var message: String?

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
                     ? "Exports are signed by the Cherri Helper on your own Mac, over an encrypted connection on your local network. Nothing is sent to the Cherri server. Your Mac still contacts Apple's servers to sign."
                     : "Exports are signed by the custom signing server run by the app's developer.")
                    .foregroundStyle(Color.helperText)
            }

            if mode == LocalSigner.macMode {
                // Shown first because the helper has to be on the Mac before pairing makes sense.
                Section {
                    Link(destination: LocalSigner.helperDownloadURL) {
                        Label("Download Cherri Helper", systemImage: "arrow.down.circle")
                    }

                    // Sends the link, not the file: the Mac opens it and downloads straight from GitHub, so nothing big crosses AirDrop.
                    ShareLink(item: LocalSigner.helperDownloadURL,
                              subject: Text("Cherri Helper for Mac"),
                              message: Text("Download Cherri Helper for your Mac.")) {
                        Label("Send Download Link to Your Mac", systemImage: "laptopcomputer.and.iphone")
                    }
                } header: {
                    Text("Get Cherri Helper")
                } footer: {
                    Text("Cherri Helper is a free Mac app, macOS 13 or later. Download it here and AirDrop the file to your Mac, or send the link to your Mac with AirDrop and let it download there.")
                        .foregroundStyle(Color.helperText)
                }

                Section {
                    HStack {
                        Text("Paired Mac")
                        Spacer()
                        Text(paired && !macName.isEmpty ? macName : "Not paired")
                            .foregroundStyle(Color.helperText)
                    }

                    Button(paired ? "Scan a New QR Code" : "Scan QR Code") { showingScanner = true }
                    Button("Paste Pairing Link") { pasteLink() }

                    if paired {
                        Button {
                            runTest()
                        } label: {
                            HStack {
                                Text("Test Connection")
                                if working {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(working)

                        Button("Unpair", role: .destructive) {
                            MacPairingStore.clear()
                            paired = false
                            message = nil
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.helperText)
                    }
                } header: {
                    Text("Your Mac")
                } footer: {
                    Text("Open Cherri Helper on your Mac, choose Pair an iPhone, and scan the code. Your phone and Mac need to be on the same Wi-Fi network. If this is set to My Mac, Export never falls back to the Cherri server.")
                        .foregroundStyle(Color.helperText)
                }
            }
        }
        .navigationTitle("Signing")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingScanner) {
            ScannerSheet(onCode: accept)
        }
    }

    // Saves a valid pairing link and tests it right away, so the person sees whether it worked.
    private func accept(_ text: String) -> Bool {
        guard let pairing = PairingLink.parse(text) else {
            message = "That isn't a Cherri Helper pairing code."
            return false
        }
        MacPairingStore.save(pairing)
        paired = true
        showingScanner = false
        runTest()
        return true
    }

    private func pasteLink() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            message = "The clipboard is empty. Copy the pairing link from the helper's menu first."
            return
        }
        _ = accept(text)
    }

    private func runTest() {
        working = true
        message = nil
        Task {
            message = await LocalSigner.testConnection()
            working = false
        }
    }
}


// ===================================
// SCANNER SHEET
// ===================================

private struct ScannerSheet: View {
    let onCode: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRScannerView(onCode: onCode, onProblem: { problem = $0 })
                    .ignoresSafeArea()

                Text(problem ?? "Point the camera at the QR code on your Mac.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
