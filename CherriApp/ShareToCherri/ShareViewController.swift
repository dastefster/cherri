// ===================================
// Share to Cherri Shortcuts
// v0.0.2 BUILD 2026-10-25 07:20
// Share extension: takes a Shortcuts iCloud link from the share sheet, hands it to Cherri Shortcuts through a shared App Group, and opens the app to import it.
// dev by @dastefster 🍒🔨
// ===================================

import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// ===================================
// HANDOFF
// ===================================

// Keep these three values identical to SharedImport.swift in the app. The extension and the app are separate programs, so the link travels between them through this group's UserDefaults.
private enum Handoff {
    static let groupID = "group.com.dastefster.CherriApp"
    static let linkKey = "pendingImportLink"
    static let dateKey = "pendingImportDate"
    static let openURL = URL(string: "cherrishortcuts://import")!
    static let linkPattern = #"https://(?:www\.)?icloud\.com/shortcuts/[A-Za-z0-9]+"#

    static func link(in text: String) -> String? {
        guard let range = text.range(of: linkPattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    static func save(_ link: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: groupID) else { return false }
        defaults.set(link, forKey: linkKey)
        defaults.set(Date().timeIntervalSince1970, forKey: dateKey)
        return true
    }
}

// ===================================
// SCREEN STATE
// ===================================

@MainActor
private final class ShareModel: ObservableObject {
    enum Phase {
        case working
        case opening
        case openByHand
        case notAShortcutLink
        case failed
    }

    @Published var phase = Phase.working
    var onDone: () -> Void = {}
    var onOpenApp: () -> Void = {}
}

private struct ShareStatusView: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if model.phase == .working || model.phase == .opening {
                ProgressView()
            }
            if model.phase == .openByHand {
                Button("Open Cherri Shortcuts") { model.onOpenApp() }
                    .buttonStyle(.borderedProminent)
            }
            if model.phase != .working && model.phase != .opening {
                Button("Done") { model.onDone() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var icon: String {
        switch model.phase {
        case .working, .opening: return "arrow.down.circle"
        case .openByHand: return "checkmark.circle"
        case .notAShortcutLink, .failed: return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch model.phase {
        case .working, .opening: return .accentColor
        case .openByHand: return .green
        case .notAShortcutLink, .failed: return .orange
        }
    }

    private var title: String {
        switch model.phase {
        case .working: return "Reading the link…"
        case .opening: return "Opening Cherri Shortcuts…"
        case .openByHand: return "Link saved"
        case .notAShortcutLink: return "That isn't a Shortcuts link"
        case .failed: return "Couldn't save the link"
        }
    }

    private var detail: String {
        switch model.phase {
        case .working, .opening: return ""
        case .openByHand: return "Open Cherri Shortcuts and it will import this shortcut."
        case .notAShortcutLink: return "Share a shortcut's iCloud link from the Shortcuts app."
        case .failed: return "Please try again. If it keeps happening, use Import inside Cherri Shortcuts instead."
        }
    }
}

// ===================================
// SHARE VIEW CONTROLLER
// ===================================

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        model.onDone = { [weak self] in self?.finish() }
        model.onOpenApp = { [weak self] in self?.openApp() }

        let host = UIHostingController(rootView: ShareStatusView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)

        Task { await handleSharedItems() }
    }

    // ===================================
    // READ THE SHARED LINK
    // ===================================

    private func handleSharedItems() async {
        guard let link = await findLink() else {
            model.phase = .notAShortcutLink
            return
        }
        guard Handoff.save(link) else {
            model.phase = .failed
            return
        }
        openApp()
    }

    // Shortcuts hands over a web URL, but a link copied as text can arrive too, so both are read.
    private func findLink() async -> String? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                   let text = (value as? URL)?.absoluteString ?? (value as? String),
                   let link = Handoff.link(in: text) {
                    return link
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                   let text = value as? String,
                   let link = Handoff.link(in: text) {
                    return link
                }
            }
            if let text = item.attributedContentText?.string, let link = Handoff.link(in: text) {
                return link
            }
        }
        return nil
    }

    // ===================================
    // OPEN THE APP
    // ===================================

    // A share extension has no official way to open its app. UIApplication still sits at the end of the responder chain, and calling its public open method through the runtime is the long-standing workaround. If iOS refuses, the person is told to open the app by hand; the link is already saved either way.
    private func openApp() {
        model.phase = .opening

        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                // The options argument is a dictionary on UIApplication but an options object on UIScene (which comes first in the chain on current iOS). Passing a dictionary to the scene crashed the extension, so it gets nil, which both accept.
                typealias OpenFunction = @convention(c) (AnyObject, Selector, URL, AnyObject?, ((Bool) -> Void)?) -> Void
                let function = unsafeBitCast(current.method(for: selector), to: OpenFunction.self)
                function(current, selector, Handoff.openURL, nil) { [weak self] opened in
                    DispatchQueue.main.async {
                        if opened {
                            self?.finish()
                        } else {
                            self?.model.phase = .openByHand
                        }
                    }
                }
                return
            }
            responder = current.next
        }
        model.phase = .openByHand
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
