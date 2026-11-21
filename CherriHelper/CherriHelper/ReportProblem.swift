// ===================================
// Report a Problem
// v0.0.3 BUILD 2026-11-21@12:14
// Opens an email to support with this Mac's basic info and the helper's log, so nobody has to dig through files to ask for help.
// dev by @dastefster 🍒🔨
// ===================================

import AppKit


// ===================================
// REPORT
// ===================================

@MainActor
enum ReportProblem {
    static let supportEmail = "dastefster@gmail.com"
    private static let subject = "Cherri Helper problem report"

    // Apple Mail can attach the log itself. Other mail apps get the same details in the message body, and the log is shown in Finder to drag in.
    static func open(status: String, launchAtLogin: Bool) {
        let logCopy = copyOfLog()
        var items: [Any] = [intro + diagnostics(status: status, launchAtLogin: launchAtLogin, logLines: 60)]
        if let logCopy { items.append(logCopy) }

        if let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: items) {
            service.recipients = [supportEmail]
            service.subject = subject
            service.perform(withItems: items)
            return
        }

        openWithMailto(status: status, launchAtLogin: launchAtLogin, logCopy: logCopy)
    }

    // For anyone who reads their email in a browser or has no account set up in Mail: the whole report goes on the clipboard,
    // and the log is shown in Finder so it can be attached by hand.
    static func copyReport(status: String, launchAtLogin: Bool) {
        let text = "To: \(supportEmail)\nSubject: \(subject)\n\n" + intro + diagnostics(status: status, launchAtLogin: launchAtLogin, logLines: 200)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if let logCopy = copyOfLog() { NSWorkspace.shared.activateFileViewerSelecting([logCopy]) }
    }

    private static let intro = "Please describe what went wrong here:\n\n\n\n----- Details for support (you can read and edit these) -----\n"

    private static func openWithMailto(status: String, launchAtLogin: Bool, logCopy: URL?) {
        // A mailto link has to stay short, so only the newest log lines go in the body.
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: intro + diagnostics(status: status, launchAtLogin: launchAtLogin, logLines: 12)),
        ]

        if let url = components.url { NSWorkspace.shared.open(url) }
        if let logCopy {
            NSWorkspace.shared.activateFileViewerSelecting([logCopy])
        }
    }


    // ===================================
    // DETAILS
    // ===================================

    // No computer name, serial number or account details. Only what is needed to reproduce a problem.
    static func diagnostics(status: String, launchAtLogin: Bool, logLines: Int) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        var lines = [
            "Cherri Helper \(version) (build \(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: ""))",
            "Mac: \(sysctlString("hw.model")), \(sysctlString("machdep.cpu.brand_string"))",
            "Status: \(status)",
            "Start at login: \(launchAtLogin ? "yes" : "no")",
            "",
            "Recent log:",
        ]
        lines.append(contentsOf: recentLog(lines: logLines))
        return lines.joined(separator: "\n")
    }

    private static func recentLog(lines count: Int) -> [String] {
        guard let text = try? String(contentsOf: Log.url, encoding: .utf8) else { return ["(no log yet)"] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).suffix(count).map(String.init)
    }

    // A copy, so the helper can keep writing to the real log while Mail holds the attachment.
    private static func copyOfLog() -> URL? {
        guard FileManager.default.fileExists(atPath: Log.url.path) else { return nil }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("CherriHelper-log.txt")
        try? FileManager.default.removeItem(at: copy)
        do { try FileManager.default.copyItem(at: Log.url, to: copy) } catch { return nil }
        return copy
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }
}
