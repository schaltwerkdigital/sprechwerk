import Foundation

/// The team's shared dictionary: names and terms everyone at Schaltwerk dictates. It is a
/// Markdown file in the Brain vault, so the team edits it in Obsidian and it reaches every
/// Mac with the vault sync. Personal terms stay in the app's settings and win over it.
///
/// Format. `##` headings pick the section (case does not matter), `###` headings only group
/// entries, anything else is ignored:
///
///     ## Begriffe
///     - Velomanufaktur
///     - Abacus (Schweizer ERP)          the note in parentheses at the end is dropped
///     ## Ersetzungen
///     - Schenobel, Schenobl → Channable   several spoken forms, separated by commas
///     ## Kontext
///     Schaltwerk Digital ist eine E-Commerce-Agentur ...
///
/// `->` and `=>` work like `→`. HTML comments (`<!-- -->`) and the frontmatter are skipped.
struct TeamVocabulary: Equatable {
    var terms: [String] = []
    var replacements: [TermReplacement] = []
    /// Background for the AI modes, used while the personal "Kontext" is empty.
    var context: String = ""

    var isEmpty: Bool {
        terms.isEmpty && replacements.isEmpty && context.isEmpty
    }

    /// Where the file lives inside the Brain vault.
    static let vaultRelativePath = "agency/schaltwerk/team-wortschatz.md"
    /// Subheading under which entries added in the app land, so the team can sort them later.
    static let addedInAppHeading = "### Aus der App erg\u{00E4}nzt"

    enum Section: Equatable {
        case terms
        case replacements
        case context
        case other
    }

    // MARK: - Reading

    static func parse(_ markdown: String) -> TeamVocabulary {
        var vocabulary = TeamVocabulary()
        var seenTerms = Set<String>()
        var seenSpoken = Set<String>()
        var contextLines: [String] = []
        var section = Section.other

        for line in contentLines(of: markdown) {
            if let heading = level2Heading(line) {
                section = Self.section(forHeading: heading)
                continue
            }
            if isHeading(line) { continue }

            switch section {
            case .terms:
                guard let item = listItem(line) else { continue }
                // An arrow means a replacement, even when it was put under "Begriffe".
                let rules = replacementRules(item)
                if !rules.isEmpty {
                    for rule in rules where seenSpoken.insert(rule.id).inserted {
                        vocabulary.replacements.append(rule)
                    }
                    continue
                }
                let term = withoutTrailingNote(item)
                guard !term.isEmpty, seenTerms.insert(term.lowercased()).inserted else { continue }
                vocabulary.terms.append(term)
            case .replacements:
                guard let item = listItem(line) else { continue }
                for rule in replacementRules(item) where seenSpoken.insert(rule.id).inserted {
                    vocabulary.replacements.append(rule)
                }
            case .context:
                let text = line.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { contextLines.append(text) }
            case .other:
                continue
            }
        }
        vocabulary.context = contextLines.joined(separator: " ")
        return vocabulary
    }

    static func section(forHeading heading: String) -> Section {
        let name = heading.lowercased()
        if name.contains("ersetz") { return .replacements }
        if name.contains("kontext") { return .context }
        if name.contains("begriff") || name.contains("namen") { return .terms }
        return .other
    }

    // MARK: - Writing

    /// The file with `term` added to "Begriffe", unchanged when the team has it already.
    static func adding(term: String, to markdown: String) -> String {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty,
              !parse(markdown).terms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame })
        else { return markdown }
        return inserting("- \(term)", into: .terms, heading: "## Begriffe", of: markdown)
    }

    /// The file with `rule` added to "Ersetzungen", unchanged when the team has these spoken
    /// words already.
    static func adding(_ rule: TermReplacement, to markdown: String) -> String {
        let spoken = rule.spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let written = rule.written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty, !written.isEmpty,
              !parse(markdown).replacements.contains(where: { $0.id == spoken.lowercased() })
        else { return markdown }
        return inserting("- \(spoken) \u{2192} \(written)", into: .replacements, heading: "## Ersetzungen", of: markdown)
    }

    /// Puts `entry` at the end of the section, under `addedInAppHeading`. Without the section
    /// it is appended to the file with its heading.
    private static func inserting(_ entry: String, into target: Section, heading: String, of markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        let frontmatterEnd = frontmatterLineCount(lines)

        var sectionStart: Int?
        var sectionEnd = lines.count
        var insideComment = false
        for index in lines.indices where index >= frontmatterEnd {
            let line = lines[index]
            if line.contains("<!--") && !line.contains("-->") { insideComment = true }
            if insideComment {
                if line.contains("-->") { insideComment = false }
                continue
            }
            if let name = level2Heading(line) ?? level1Heading(line) {
                if sectionStart != nil {
                    sectionEnd = index
                    break
                }
                if level2Heading(line) != nil, section(forHeading: name) == target {
                    sectionStart = index
                }
            }
        }

        guard let start = sectionStart else {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            lines += ["", heading, "", addedInAppHeading, "", entry, ""]
            return lines.joined(separator: "\n")
        }

        // Last non-empty line of the section; the entry goes right after it.
        var insertAt = sectionEnd
        while insertAt > start + 1, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertAt -= 1
        }
        let hasAppGroup = lines[(start + 1)..<sectionEnd].contains {
            $0.trimmingCharacters(in: .whitespaces) == addedInAppHeading
        }
        // Entries are only appended at the end, so the app's group is always the last one.
        var block = hasAppGroup ? [entry] : ["", addedInAppHeading, "", entry]
        if insertAt == sectionEnd, sectionEnd < lines.count { block.append("") }
        lines.insert(contentsOf: block, at: insertAt)
        return lines.joined(separator: "\n")
    }

    // MARK: - Line helpers

    /// The lines that carry content: without frontmatter and HTML comments.
    private static func contentLines(of markdown: String) -> [String] {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = text.components(separatedBy: "\n")
        let frontmatterEnd = frontmatterLineCount(lines)
        text = lines.dropFirst(frontmatterEnd).joined(separator: "\n")
        if let comment = try? NSRegularExpression(pattern: "<!--.*?-->", options: [.dotMatchesLineSeparators]) {
            text = comment.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        return text.components(separatedBy: "\n")
    }

    /// Lines taken by a leading `---` frontmatter block, 0 without one.
    private static func frontmatterLineCount(_ lines: [String]) -> Int {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return 0 }
        for index in lines.indices.dropFirst() where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            return index + 1
        }
        return 0
    }

    private static func level1Heading(_ line: String) -> String? {
        heading(line, level: 1)
    }

    private static func level2Heading(_ line: String) -> String? {
        heading(line, level: 2)
    }

    private static func heading(_ line: String, level: Int) -> String? {
        let marker = String(repeating: "#", count: level) + " "
        guard line.hasPrefix(marker) else { return nil }
        return line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
    }

    private static func isHeading(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }

    /// The text of a `- `, `* ` or `+ ` list item, without links and code marks.
    private static func listItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, "-*+".contains(marker),
              trimmed.dropFirst().first == " " else { return nil }
        var item = String(trimmed.dropFirst(2))
        // [[ziel|Anzeige]] and [[ziel]] read as the shown text.
        if let link = try? NSRegularExpression(pattern: "\\[\\[(?:[^\\]|]*\\|)?([^\\]]*)\\]\\]") {
            item = link.stringByReplacingMatches(in: item, range: NSRange(item.startIndex..., in: item), withTemplate: "$1")
        }
        item = item.replacingOccurrences(of: "`", with: "")
        return item.trimmingCharacters(in: .whitespaces)
    }

    /// "Abacus (Schweizer ERP)" -> "Abacus". Only a note at the very end, after a space.
    private static func withoutTrailingNote(_ item: String) -> String {
        guard item.hasSuffix(")"), let open = item.range(of: " (", options: .backwards) else { return item }
        return String(item[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    private static func replacementRules(_ item: String) -> [TermReplacement] {
        for arrow in ["\u{2192}", "->", "=>"] {
            guard let range = item.range(of: arrow) else { continue }
            let written = withoutTrailingNote(item[range.upperBound...].trimmingCharacters(in: .whitespaces))
            guard !written.isEmpty else { return [] }
            return item[..<range.lowerBound]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { TermReplacement(spoken: $0, written: written) }
        }
        return []
    }
}

// MARK: - Personal and team vocabulary together

extension TextImprovementSettings {
    /// The personal settings with the team vocabulary added. Personal entries win: a personal
    /// replacement for the same spoken words replaces the team's, and the team context only
    /// applies while the personal one is empty.
    func adding(_ team: TeamVocabulary) -> TextImprovementSettings {
        var settings = self
        settings.teamTerms = team.terms
        settings.teamReplacements = team.replacements
        if settings.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.context = team.context
        }
        return settings
    }

    /// Terms the transcript cleanup corrects to: personal ones first, then the team's.
    var correctionTerms: [String] {
        var seen = Set<String>()
        return (customTerms + teamTerms).filter { seen.insert($0.lowercased()).inserted }
    }

    /// Fixed replacements: personal ones, then the team's for words without a personal rule.
    var allReplacements: [TermReplacement] {
        let personal = Set(replacements.map(\.id))
        return replacements + teamReplacements.filter { !personal.contains($0.id) }
    }

    /// Only the team entries that appear in `text`. The team list is long and the language
    /// model on the Mac has little room; a term that was not said needs no protection.
    func narrowingTeamTerms(to text: String) -> TextImprovementSettings {
        var settings = self
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        settings.teamTerms = teamTerms.filter { text.range(of: $0, options: options) != nil }
        settings.teamReplacements = teamReplacements.filter { text.range(of: $0.written, options: options) != nil }
        return settings
    }
}
