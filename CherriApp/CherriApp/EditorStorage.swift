// ===================================
// Editor Storage
// v0.0.1 BUILD 2026-11-23 08:10
// Keeps the editor's code (and the code from the last Clear) in files in the app's private storage instead of UserDefaults, with one backup copy of the code. The one place that knows where the code lives, so iCloud can mirror it later without touching the editor.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

// ===================================
// STORAGE
// ===================================

nonisolated struct EditorFileStorage {
    nonisolated enum Slot {
        case source
        case clearedBackup

        var fileName: String {
            switch self {
            case .source: return "editor-source.txt"
            case .clearedBackup: return "editor-cleared.txt"
            }
        }

        // Only the code itself gets a backup. The cleared copy already is one.
        var backupFileName: String? {
            switch self {
            case .source: return "editor-source.backup.txt"
            case .clearedBackup: return nil
            }
        }

        // Where older versions of the app kept it. Read once to move it over, then removed.
        var legacyKey: String {
            switch self {
            case .source: return "cherriSource"
            case .clearedBackup: return "clearedBackup"
            }
        }
    }

    private let directory: URL
    private let defaults: UserDefaults

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("CherriApp", isDirectory: true)
    }

    init(directory: URL = EditorFileStorage.defaultDirectory, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
    }

    // nil means there is nothing saved anywhere yet (a first launch). An empty string is a real answer: the person cleared the editor.
    func load(_ slot: Slot) -> String? {
        let file = url(slot.fileName)
        if let text = read(file) { return text }

        // A file that exists but can't be read is set aside instead of deleted, so nothing is ever destroyed on a guess.
        if FileManager.default.fileExists(atPath: file.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            try? FileManager.default.moveItem(at: file, to: url("\(slot.fileName).damaged-\(stamp)"))
        }

        // Older versions kept this in UserDefaults. It only leaves there once the file has been written and read back identical.
        if let legacy = defaults.string(forKey: slot.legacyKey) {
            if save(legacy, slot), read(file) == legacy {
                defaults.removeObject(forKey: slot.legacyKey)
                if slot == .source { refreshBackup() }
            }
            return legacy
        }

        if let backupName = slot.backupFileName, let text = read(url(backupName)) { return text }
        return nil
    }

    @discardableResult
    func save(_ text: String, _ slot: Slot) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url(slot.fileName), options: .atomic)
            return true
        } catch {
            print("[EditorStorage] Save failed: \(error)")
            return false
        }
    }

    // Copies the code as it stands to the backup file. An empty editor never replaces a backup, so clearing and relaunching can't wipe the last good copy.
    func refreshBackup() {
        guard let name = Slot.source.backupFileName,
              let text = read(url(Slot.source.fileName)), !text.isEmpty else { return }
        try? Data(text.utf8).write(to: url(name), options: .atomic)
    }

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    private func read(_ file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// ===================================
// STORE
// ===================================

// The editor's code, shared by the main screen and Settings. Typing is saved shortly after it pauses, and always when the app leaves the screen.
final class EditorSourceStore: ObservableObject {
    static let shared = EditorSourceStore()

    @Published var text: String {
        didSet { scheduleSave() }
    }

    // The code from the last Clear. Saved at once: it only changes on a deliberate tap, and Restore has to survive a quit right after.
    @Published var clearedBackup: String {
        didSet { storage.save(clearedBackup, .clearedBackup) }
    }

    private let storage: EditorFileStorage
    private var dirty = false
    private var saveTask: Task<Void, Never>?

    init(storage: EditorFileStorage = EditorFileStorage(), startingText: String = StarterCode.text) {
        self.storage = storage
        text = storage.load(.source) ?? startingText
        clearedBackup = storage.load(.clearedBackup) ?? ""

        // Off the main thread: a big script shouldn't slow the launch for a safety copy.
        Task.detached(priority: .utility) { storage.refreshBackup() }

        #if canImport(UIKit)
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            }
        }
        #endif
    }

    // Writes any typing that hasn't been saved yet.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard dirty else { return }
        // Stays dirty if the write fails, so the next keystroke or the next time the app leaves the screen tries again.
        if storage.save(text, .source) { dirty = false }
    }

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
