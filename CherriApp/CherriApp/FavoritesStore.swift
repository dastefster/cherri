// ===================================
// Favorites
// v0.0.2 BUILD 2026-11-18 19:01
// Remembers which actions are starred and in what order. Saved by action name in its own small file with one backup copy, so a catalog update can never touch it.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import Combine

// ===================================
// STORAGE
// ===================================

// The only part that knows where favorites live, so iCloud can mirror or replace it later without touching the store or the picker.
nonisolated struct FavoritesStorage {
    private struct Payload: Codable {
        var version = 1
        var names: [String]
    }

    private let fileURL: URL
    private var backupURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("favorites.backup.json") }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("CherriApp", isDirectory: true)
    }

    init(directory: URL = FavoritesStorage.defaultDirectory) {
        fileURL = directory.appendingPathComponent("favorites.json")
    }

    // A missing file is a first launch. A damaged one is set aside instead of deleted, and the last good backup takes its place.
    func load() -> [String] {
        if let names = read(fileURL) { return names }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let setAside = fileURL.deletingLastPathComponent().appendingPathComponent("favorites.damaged-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: setAside)
        }

        return read(backupURL) ?? []
    }

    func save(_ names: [String]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            // The file about to be replaced becomes the backup, but only if it was readable.
            if read(fileURL) != nil {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }

            let data = try JSONEncoder().encode(Payload(names: names))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[Favorites] Save failed: \(error)")
        }
    }

    private func read(_ url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload.names
    }
}

// ===================================
// STORE
// ===================================

final class FavoritesStore: ObservableObject {
    // A softer gold than the Premium crown, so a star and a crown don't read as the same thing.
    private static let tintUIColor = UIColor(red: 1.0, green: 0.78, blue: 0.15, alpha: 1)
    static let tint = Color(tintUIColor)

    // The tint mixed into the normal row color. It's solid on purpose: a see-through tint lets the row underneath show through while one is being dragged.
    static let rowBackground = Color(UIColor { traits in
        let base = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
        return base.mixed(with: FavoritesStore.tintUIColor, amount: traits.userInterfaceStyle == .dark ? 0.16 : 0.32)
    })

    // Includes names the current catalog doesn't have, so a removed action comes back if a later update restores it.
    @Published private(set) var names: [String]

    private let storage: FavoritesStorage

    init(storage: FavoritesStorage = FavoritesStorage()) {
        self.storage = storage
        names = storage.load()
    }

    func contains(_ name: String) -> Bool {
        names.contains(name)
    }

    func toggle(_ name: String) {
        if let index = names.firstIndex(of: name) {
            names.remove(at: index)
        } else {
            names.append(name)
        }
        storage.save(names)
    }

    // The picker moves what it shows, which can leave out names the catalog no longer has. Those stay saved, after the visible ones.
    func move(visible: [String], from offsets: IndexSet, to destination: Int) {
        var reordered = visible
        reordered.move(fromOffsets: offsets, toOffset: destination)
        names = reordered + names.filter { !visible.contains($0) }
        storage.save(names)
    }

    func remove(visible: [String], at offsets: IndexSet) {
        let removed = Set(offsets.map { visible[$0] })
        names.removeAll { removed.contains($0) }
        storage.save(names)
    }
}

// ===================================
// COLOR MIXING
// ===================================

private extension UIColor {
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, alpha: 1)
    }
}
