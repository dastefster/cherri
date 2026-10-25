// ===================================
// Shortcut Importer
// v0.0.5 BUILD 2026-10-25 07:40
// Downloads a shortcut from a Shortcuts iCloud share link and turns it back into Cherri code for the editor. Only runs when the person taps Import.
// dev by @dastefster 🍒🔨
// ===================================

import Foundation
import Cherri

// ===================================
// IMPORTER
// ===================================

enum ShortcutImporter {
    struct Imported {
        let name: String
        let code: String
        // Actions Cherri doesn't know come back as rawAction("identifier", ...), which can lose settings and may not
        // run once compiled, so the editor warns about them. Each identifier is listed once, in the order found.
        let unsupportedActions: [String]
        let link: String
    }

    // A readable headline for the person, plus the raw technical text that goes into the support form.
    struct Failure: LocalizedError {
        let headline: String
        let details: String
        // Mistakes the person can fix themselves (wrong link) don't need the support button.
        let offersSupport: Bool
        // True when iCloud says the link doesn't exist. Right after a share that can just mean it isn't published yet.
        var isMissing = false

        var errorDescription: String? { headline }
    }

    private static let linkPattern = #"https://(?:www\.)?icloud\.com/shortcuts/[A-Za-z0-9]+"#
    // A shortcut plist is small; anything past this is not a shortcut and shouldn't be loaded into memory.
    private static let maxBytes = 20_000_000

    // ===================================
    // LINK
    // ===================================

    // Pulls the first iCloud shortcut link out of whatever was pasted, so a link inside a message still works.
    static func extractLink(from text: String) -> String? {
        guard let range = text.range(of: linkPattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    // ===================================
    // IMPORT
    // ===================================

    static func importShortcut(from text: String) async throws -> Imported {
        guard let link = extractLink(from: text) else {
            throw Failure(
                headline: "That doesn't look like a Shortcuts iCloud link. In the Shortcuts app, open the share menu for a shortcut and tap Copy iCloud Link.",
                details: "Not an iCloud shortcut link.",
                offersSupport: false
            )
        }

        let record = try await fetchRecord(link: link)
        let plist = try await download(record.downloadURL)

        let name = record.name
        let decompiled = await Task.detached(priority: .userInitiated) { () -> (code: String, error: NSError?) in
            var error: NSError?
            let code = CherriDecompile(plist, name, &error)
            return (code, error)
        }.value

        if let error = decompiled.error {
            throw Failure(
                headline: "This shortcut uses something the importer can't read yet.",
                details: "Import failed: \(error.localizedDescription) | Link: \(link)",
                offersSupport: true
            )
        }

        return Imported(
            name: name,
            code: withName(decompiled.code, name: name),
            unsupportedActions: rawActionIdentifiers(in: decompiled.code),
            link: link
        )
    }

    // ===================================
    // UNSUPPORTED ACTIONS
    // ===================================

    private static let rawActionPattern = try? NSRegularExpression(pattern: #"rawAction\(\s*"([^"]+)""#)

    static func rawActionIdentifiers(in code: String) -> [String] {
        guard let pattern = rawActionPattern else { return [] }
        let whole = NSRange(code.startIndex..., in: code)
        var found: [String] = []
        for match in pattern.matches(in: code, range: whole) {
            guard let range = Range(match.range(at: 1), in: code) else { continue }
            let identifier = String(code[range])
            if !found.contains(identifier) { found.append(identifier) }
        }
        return found
    }

    // ===================================
    // NETWORK
    // ===================================

    private struct Record {
        let name: String
        let downloadURL: URL
    }

    private struct RecordResponse: Decodable {
        struct Fields: Decodable {
            struct Named: Decodable { let value: String? }
            struct Shortcut: Decodable {
                struct Value: Decodable { let downloadURL: String? }
                let value: Value?
            }
            let name: Named?
            let shortcut: Shortcut?
        }
        let fields: Fields?
    }

    // iCloud's share API answers with a small JSON record that holds the shortcut's name and a one-off download URL.
    private static func fetchRecord(link: String) async throws -> Record {
        let recordLink = link.replacingOccurrences(of: "/shortcuts/", with: "/shortcuts/api/records/")
        guard let url = URL(string: recordLink) else {
            throw Failure(headline: "That link couldn't be read.", details: "Bad record URL: \(recordLink)", offersSupport: false)
        }

        let data = try await get(url, what: "the shortcut's details")
        guard let response = try? JSONDecoder().decode(RecordResponse.self, from: data),
              let urlString = response.fields?.shortcut?.value?.downloadURL,
              let downloadURL = URL(string: urlString),
              downloadURL.scheme == "https" else {
            throw Failure(
                headline: "iCloud didn't return a shortcut for that link. It may have been deleted or the sharing turned off.",
                details: "Record response had no download URL. Link: \(link)",
                offersSupport: true
            )
        }

        return Record(name: response.fields?.name?.value ?? "Shortcut", downloadURL: downloadURL)
    }

    private static func download(_ url: URL) async throws -> Data {
        let data = try await get(url, what: "the shortcut file")
        guard data.count <= maxBytes else {
            throw Failure(headline: "That file is too large to be a shortcut.", details: "Download was \(data.count) bytes.", offersSupport: false)
        }
        return data
    }

    private static func get(_ url: URL, what: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                // iCloud answers 500, not 404, when the record lookup is for a link that no longer exists (replaced
                // or unshared), so on that step a 500 most likely means a stale link.
                let missing = http.statusCode == 404 || (http.statusCode == 500 && what == "the shortcut's details")
                throw Failure(
                    headline: missing
                        ? "iCloud couldn't find that shortcut. The link may be old or sharing may be off. Copy a fresh iCloud link from the Shortcuts app and try again."
                        : "iCloud had a problem sending \(what) (HTTP \(http.statusCode)). Try again in a moment.",
                    details: "HTTP \(http.statusCode) fetching \(what) from \(url.absoluteString).",
                    // A missing link or an iCloud server error isn't something support can fix, so only odd statuses offer it.
                    offersSupport: !missing && !(500...599).contains(http.statusCode),
                    isMissing: missing
                )
            }
            return data
        } catch let failure as Failure {
            throw failure
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw Failure(headline: "You're offline. Connect to the internet and try again.", details: error.localizedDescription, offersSupport: false)
        } catch let error as URLError where error.code == .timedOut {
            throw Failure(headline: "iCloud took too long to answer. Try again in a moment.", details: error.localizedDescription, offersSupport: false)
        } catch {
            throw Failure(headline: "Couldn't download the shortcut. \(error.localizedDescription)", details: error.localizedDescription, offersSupport: true)
        }
    }

    // ===================================
    // NAME
    // ===================================

    // The decompiler drops the shortcut's name, and Export reads it from "#define name", so put it back at the top.
    private static func withName(_ code: String, name: String) -> String {
        if code.range(of: #"^[ \t]*#define[ \t]+name\b"#, options: [.regularExpression]) != nil
            || code.contains("\n#define name ") {
            return code
        }

        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return code }

        return "#define name \(String(cleaned.prefix(80)))\n\(code)"
    }
}
