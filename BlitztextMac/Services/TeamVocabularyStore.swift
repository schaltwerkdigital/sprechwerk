import Foundation
import Observation

/// Loads the team vocabulary from the Brain vault and keeps it current. The file is read
/// again when it changed: before each dictation, when the dictionary settings open and every
/// five minutes, so an entry a colleague adds in Obsidian arrives with the next vault sync.
@Observable
@MainActor
final class TeamVocabularyStore {
    private(set) var vocabulary = TeamVocabulary()
    /// The file in use, nil while none was found.
    private(set) var fileURL: URL?
    private(set) var lastLoaded: Date?
    /// Why there is no vocabulary or the last change failed, nil when all is well.
    private(set) var problem: String?

    /// Path chosen in the settings; empty means: look for the Brain vault.
    private var configuredPath = ""
    @ObservationIgnored private var loadedModificationDate: Date?
    @ObservationIgnored private var watchTask: Task<Void, Never>?

    var usesDetectedVault: Bool { configuredPath.isEmpty }

    func configure(path: String) {
        configuredPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        fileURL = nil
        reload()
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                self?.refreshIfChanged()
            }
        }
    }

    /// Reads the file again when it moved or changed since the last read.
    func refreshIfChanged() {
        guard let url = resolvedURL(), url == fileURL,
              let modified = Self.modificationDate(of: url), modified == loadedModificationDate
        else {
            reload()
            return
        }
    }

    func reload() {
        guard let url = resolvedURL() else {
            fileURL = nil
            vocabulary = TeamVocabulary()
            loadedModificationDate = nil
            problem = usesDetectedVault
                ? "Kein Brain-Vault gefunden. Erwartet wird \(TeamVocabulary.vaultRelativePath) im Vault."
                : "Die gew\u{00E4}hlte Datei gibt es nicht mehr."
            return
        }
        fileURL = url
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            vocabulary = TeamVocabulary.parse(text)
            loadedModificationDate = Self.modificationDate(of: url)
            lastLoaded = Date()
            problem = vocabulary.isEmpty ? "Die Datei enth\u{00E4}lt noch keine Begriffe." : nil
        } catch {
            // Keep the last good list: a sync may be writing the file right now.
            loadedModificationDate = nil
            problem = "Die Datei l\u{00E4}sst sich nicht lesen. Darf Sprechwerk auf den Ordner zugreifen?"
        }
    }

    // MARK: - Adding for everyone

    /// Writes the term into the team file. False when there is no file or it is not writable.
    @discardableResult
    func add(term: String) -> Bool {
        update { TeamVocabulary.adding(term: term, to: $0) }
    }

    @discardableResult
    func add(_ rule: TermReplacement) -> Bool {
        update { TeamVocabulary.adding(rule, to: $0) }
    }

    /// Reads the current file first, so an edit synced in the meantime is kept. Written in
    /// place (not atomically) so no temporary file shows up in the vault.
    private func update(_ change: (String) -> String) -> Bool {
        guard let url = fileURL ?? resolvedURL() else {
            problem = "Ohne Team-Datei l\u{00E4}sst sich nichts f\u{00FC}rs Team speichern."
            return false
        }
        do {
            let current = try String(contentsOf: url, encoding: .utf8)
            let updated = change(current)
            if updated != current {
                try updated.write(to: url, atomically: false, encoding: .utf8)
            }
            reload()
            return true
        } catch {
            problem = "Die Team-Datei lie\u{00DF} sich nicht speichern."
            return false
        }
    }

    // MARK: - Finding the file

    private func resolvedURL() -> URL? {
        if !usesDetectedVault {
            let url = URL(fileURLWithPath: (configuredPath as NSString).expandingTildeInPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return Self.detectVaultFile()
    }

    /// The vocabulary in the Brain vault: the usual place first, then every vault Obsidian knows.
    static func detectVaultFile() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [home.appendingPathComponent("Documents/DEV/brain", isDirectory: true)] + obsidianVaults()
        for root in roots {
            let candidate = root.appendingPathComponent(TeamVocabulary.vaultRelativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Vault folders from Obsidian's own list (`obsidian.json`).
    private static func obsidianVaults() -> [URL] {
        let list = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
        guard let data = try? Data(contentsOf: list),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = json["vaults"] as? [String: Any]
        else { return [] }
        return vaults.values
            .compactMap { ($0 as? [String: Any])?["path"] as? String }
            .sorted()
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
