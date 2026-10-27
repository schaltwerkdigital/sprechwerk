import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Team-Wortschatz" in the dictionary settings: the shared Schaltwerk list from the Brain
/// vault, where it comes from and how to change it. The list itself is edited in Obsidian.
struct TeamVocabularySection: View {
    @Bindable var appState: AppState
    @State private var showsAllEntries = false

    private var store: TeamVocabularyStore { appState.teamVocabulary }

    var body: some View {
        SettingsSection(title: "Team-Wortschatz") {
            Text("Kunden, Tools und Namen, die alle bei Schaltwerk diktieren. Die Liste liegt im Brain und wird in Obsidian gepflegt. Deine eigenen Eintr\u{00E4}ge unten gelten zus\u{00E4}tzlich und gehen vor.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !store.vocabulary.isEmpty {
                Text(summary)
                    .font(.ui(11.5, .semibold))
            }

            if let problem = store.problem {
                Text(problem)
                    .font(.ui(12))
                    .foregroundStyle(store.vocabulary.isEmpty ? AnyShapeStyle(BlitztextTheme.danger) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let url = store.fileURL {
                Text(Self.displayPath(url))
                    .font(.ui(11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path)
            }

            HStack(spacing: 8) {
                if let url = store.fileURL {
                    Button("Bearbeiten") { Self.open(url) }
                        .buttonStyle(SubtleButtonStyle())
                        .help("\u{00D6}ffnet die Liste in Obsidian, ohne Obsidian im Finder.")
                }
                Button("Neu laden") { store.reload() }
                    .buttonStyle(SubtleButtonStyle())
                Button("Datei w\u{00E4}hlen \u{2026}") { chooseFile() }
                    .buttonStyle(SubtleButtonStyle())
                if !store.usesDetectedVault {
                    Button("Automatisch") { appState.appSettings.teamVocabularyPath = "" }
                        .buttonStyle(SubtleButtonStyle())
                        .help("Die Liste wieder selbst im Brain-Vault suchen.")
                }
            }

            if !store.vocabulary.terms.isEmpty || !store.vocabulary.replacements.isEmpty {
                DisclosureGroup(isExpanded: $showsAllEntries) {
                    VStack(alignment: .leading, spacing: 8) {
                        FlowLayout(spacing: 5) {
                            ForEach(store.vocabulary.terms, id: \.self) { term in
                                Text(term)
                                    .font(.ui(12))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                    )
                            }
                        }

                        ForEach(store.vocabulary.replacements) { rule in
                            HStack(spacing: 6) {
                                Text(rule.spoken)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.ui(8, .semibold))
                                    .foregroundStyle(.tertiary)
                                Text(rule.written)
                                    .fontWeight(.semibold)
                            }
                            .font(.ui(12))
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text(showsAllEntries ? "Eintr\u{00E4}ge ausblenden" : "Alle Eintr\u{00E4}ge anzeigen")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { store.refreshIfChanged() }
    }

    private var summary: String {
        let vocabulary = store.vocabulary
        var text = "\(vocabulary.terms.count) Begriffe, \(vocabulary.replacements.count) Ersetzungen"
        if !vocabulary.context.isEmpty {
            text += ", Kontext f\u{00FC}r KI-Modi"
        }
        if let loaded = store.lastLoaded {
            text += " \u{00B7} geladen \(loaded.formatted(date: .omitted, time: .shortened))"
        }
        return text
    }

    private static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    /// In Obsidian when it is installed, so the vault's sync and history apply.
    private static func open(_ url: URL) {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: url.path)]
        if let obsidian = components.url, NSWorkspace.shared.urlForApplication(toOpen: obsidian) != nil {
            NSWorkspace.shared.open(obsidian)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Team-Wortschatz w\u{00E4}hlen"
        panel.prompt = "Verwenden"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.directoryURL = store.fileURL?.deletingLastPathComponent()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.appSettings.teamVocabularyPath = url.path
    }
}
