// ===================================
// Recent Shortcuts
// v0.0.1 BUILD 2026-11-23 08:10
// Keeps the last 10 shortcuts downloaded in the Import sheet on this device, so one can be copied from or imported again without downloading it twice. Stored in the app's private storage, left out of device backups, and removable one at a time or all at once. A Settings switch turns it off and deletes them.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation
import Combine

// ===================================
// MODEL
// ===================================

nonisolated struct RecentShortcut: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var link: String
    var savedAt: Date
}

// ===================================
// STORAGE
// ===================================

// An index file plus one plist file per shortcut. The index decides what exists: a plist it doesn't list is deleted on load, and an entry whose plist is gone is dropped.
nonisolated struct RecentShortcutsStorage {
    static let limit = 10
    // A shortcut plist is small. Anything past this isn't worth keeping on a phone.
    static let maxBytes = 5_000_000

    private struct Payload: Codable {
        var version = 1
        var entries: [RecentShortcut]
    }

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("recent.json") }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("CherriApp", isDirectory: true)
            .appendingPathComponent("Recent", isDirectory: true)
    }

    init(directory: URL = RecentShortcutsStorage.defaultDirectory) {
        self.directory = directory
    }

    func loadIndex() -> [RecentShortcut] {
        var entries: [RecentShortcut] = []
        if let data = try? Data(contentsOf: indexURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = (try? decoder.decode(Payload.self, from: data))?.entries ?? []
        }

        entries = entries.filter { FileManager.default.fileExists(atPath: plistURL($0.id).path) }
        removeUnlisted(keeping: Set(entries.map(\.id)))
        return entries
    }

    func saveIndex(_ entries: [RecentShortcut]) {
        do {
            try prepareDirectory()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Payload(entries: entries)).write(to: indexURL, options: .atomic)
        } catch {
            print("[Recent] Index save failed: \(error)")
        }
    }

    func writePlist(_ data: Data, for id: UUID) -> Bool {
        do {
            try prepareDirectory()
            try data.write(to: plistURL(id), options: .atomic)
            return true
        } catch {
            print("[Recent] Write failed: \(error)")
            return false
        }
    }

    func readPlist(for id: UUID) -> Data? {
        try? Data(contentsOf: plistURL(id))
    }

    func deletePlist(for id: UUID) {
        try? FileManager.default.removeItem(at: plistURL(id))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func plistURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).plist")
    }

    // Other people's shortcuts that can be downloaded again don't belong in the person's backups.
    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    private func removeUnlisted(keeping ids: Set<UUID>) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "plist" {
            if let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), ids.contains(id) { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// ===================================
// STORE
// ===================================

final class RecentShortcutsStore: ObservableObject {
    static let enabledKey = "keepRecentShortcuts"

    // On unless the person turned it off.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    // Newest first.
    @Published private(set) var entries: [RecentShortcut]

    private let storage: RecentShortcutsStorage
    private let isEnabled: () -> Bool

    init(storage: RecentShortcutsStorage = RecentShortcutsStorage(), isEnabled: @escaping () -> Bool = { RecentShortcutsStore.isEnabled }) {
        self.storage = storage
        self.isEnabled = isEnabled
        entries = isEnabled() ? storage.loadIndex() : []
    }

    // Called after every successful download. The same link again replaces its older copy and moves to the top.
    func remember(_ fetched: ShortcutImporter.Fetched) {
        guard isEnabled(), !fetched.link.isEmpty, fetched.plist.count <= RecentShortcutsStorage.maxBytes else { return }

        let id = entries.first { $0.link == fetched.link }?.id ?? UUID()
        guard storage.writePlist(fetched.plist, for: id) else { return }

        var next = entries.filter { $0.link != fetched.link }
        next.insert(RecentShortcut(id: id, name: fetched.name, link: fetched.link, savedAt: Date()), at: 0)

        for dropped in next.dropFirst(RecentShortcutsStorage.limit) { storage.deletePlist(for: dropped.id) }
        next = Array(next.prefix(RecentShortcutsStorage.limit))

        entries = next
        storage.saveIndex(next)
    }

    // A saved copy that can't be read is removed, so the list never offers something that won't open.
    func fetched(for entry: RecentShortcut) -> ShortcutImporter.Fetched? {
        guard let plist = storage.readPlist(for: entry.id), !plist.isEmpty else {
            remove(entry)
            return nil
        }
        return ShortcutImporter.Fetched(name: entry.name, plist: plist, link: entry.link)
    }

    func remove(_ entry: RecentShortcut) {
        storage.deletePlist(for: entry.id)
        entries.removeAll { $0.id == entry.id }
        storage.saveIndex(entries)
    }

    func remove(at offsets: IndexSet) {
        let removed = offsets.map { entries[$0] }
        removed.forEach(remove)
    }

    func clearAll() {
        storage.deleteAll()
        entries = []
    }

    // The Settings switch calls this when it's turned off, without needing a store of its own.
    static func deleteEverything() {
        RecentShortcutsStorage().deleteAll()
    }
}
