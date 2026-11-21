// ===================================
// Support
// v0.0.3 BUILD 2026-11-21@15:45
// Shared folders, the log file, the status file the test tools read, and the Help link.
// dev by @dastefster 🍒🔨
// ===================================

import AppKit


// ===================================
// PATHS
// ===================================

enum StoragePaths {
    static var supportFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("CherriHelper", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return folder
    }
}


// ===================================
// LOG
// ===================================

// Sizes, timings, and outcomes only. Shortcut names and contents never reach the log.
enum Log {
    private static let queue = DispatchQueue(label: "com.dastefster.CherriHelper.log")
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CherriHelper.log")

    static func write(_ message: String) {
        queue.async {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let line = "\(formatter.string(from: Date())) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}


// ===================================
// STATUS FILE
// ===================================

// Lets the test client find the port without parsing the log. It holds no secrets.
enum StatusFile {
    static func write(port: Int, serviceName: String) {
        let payload: [String: Any] = ["port": port, "service": serviceName, "version": HelperServer.version]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: StoragePaths.supportFolder.appendingPathComponent("status.json"), options: .atomic)
    }
}


// ===================================
// HELP
// ===================================

enum HelpLinks {
    static let helpURL = URL(string: "https://dastefster.github.io/cherricuts/helper/help.html")!

    static func open() {
        NSWorkspace.shared.open(helpURL)
    }
}
