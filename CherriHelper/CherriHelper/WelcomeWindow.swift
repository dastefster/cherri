// ===================================
// Welcome Window
// v0.0.1 BUILD 2026-11-21@15:45
// Opens the welcome pages on first launch, and again from Settings. Holds the flow state and the finish logic.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import Combine


// ===================================
// WINDOW
// ===================================

@MainActor
enum WelcomeWindow {
    fileprivate static var window: NSWindow?
    private static var delegate: WelcomeWindowDelegate?

    static func show() {
        if window == nil {
            let flow = WelcomeFlow()
            let created = NSWindow(contentViewController: NSHostingController(rootView: WelcomeHost(flow: flow)))
            created.title = "Welcome to Cherri Helper"
            created.styleMask = [.titled, .closable, .fullSizeContentView]
            created.titlebarAppearsTransparent = true
            created.titleVisibility = .hidden
            created.isReleasedWhenClosed = false
            created.center()

            let closing = WelcomeWindowDelegate(flow: flow) {
                WelcomeWindow.window = nil
                WelcomeWindow.delegate = nil
            }
            created.delegate = closing
            delegate = closing
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
    }
}

private final class WelcomeWindowDelegate: NSObject, NSWindowDelegate {
    private let flow: WelcomeFlow
    private let onClose: () -> Void

    init(flow: WelcomeFlow, onClose: @escaping () -> Void) {
        self.flow = flow
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        // Closing on the last page counts as finishing. Closing earlier leaves the welcome to run again until an iPhone has paired.
        Task { @MainActor in
            if flow.page == welcomeLastPage { flow.finish() }
            onClose()
        }
    }
}


// ===================================
// FLOW
// ===================================

@MainActor
final class WelcomeFlow: ObservableObject {
    @Published var page = 0
    @Published var startAtLogin: Bool
    @Published var paired = false
    private var finished = false

    init() {
        let model = HelperModel.shared
        // First run recommends starting at login. Opened again from Settings, it shows what is actually set, so Done never changes it by surprise.
        startAtLogin = model.welcomeCompleted ? model.launchAtLogin : true
    }

    func finish() {
        guard !finished else { return }
        finished = true
        let model = HelperModel.shared
        if startAtLogin != model.launchAtLogin { model.setLaunchAtLogin(startAtLogin) }
        model.completeWelcome()
    }
}


// ===================================
// HOST
// ===================================

private struct WelcomeHost: View {
    @ObservedObject var flow: WelcomeFlow
    @ObservedObject private var model = HelperModel.shared

    var body: some View {
        WelcomeView(
            page: $flow.page,
            startAtLogin: $flow.startAtLogin,
            pairingURL: model.pairingURL,
            status: model.status,
            paired: flow.paired,
            onOpenHelp: { HelpLinks.open() },
            onDone: {
                flow.finish()
                WelcomeWindow.close()
            }
        )
        .onReceive(model.$lastPhoneContact) { contact in
            // Only a connection that arrives while the pairing page is showing counts as this setup working.
            if contact != nil, flow.page == 2 { flow.paired = true }
        }
    }
}
