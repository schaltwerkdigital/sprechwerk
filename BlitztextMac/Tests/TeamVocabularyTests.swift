import XCTest

final class TeamVocabularyTests: XCTestCase {
    private let sample = """
    ---
    typ: wortschatz
    ---

    # Team-Wortschatz

    Einleitung mit - Strich, die nichts zählt.

    ## Begriffe
    <!-- Eine Zeile pro Begriff.
    - Auskommentiert
    -->

    ### Kunden
    - Velomanufaktur
    - Abacus (Schweizer ERP)
    * [[clients/beispiel-gmbh/README|Beispiel GmbH]]
    - `entitys`
    - VELOMANUFAKTUR

    ### Tools
    + Shopware
    - n acht n → n8n

    ## Ersetzungen
    - Schenobel, Schenobl → Channable
    - Superbase -> Supabase
    - ihren wegs => INWX (Domain-Registrar)
    - kaputt ohne Pfeil
    - leer →

    ## Kontext
    Schaltwerk Digital ist eine E-Commerce-Agentur.
    <!-- nur für die KI-Modi -->
    Wir arbeiten mit Shopify und Shopware.

    ## Sonstiges
    - Kein Begriff
    """

    func testParsesSectionsAndSkipsCommentsAndFrontmatter() {
        let vocabulary = TeamVocabulary.parse(sample)
        XCTAssertEqual(vocabulary.terms, ["Velomanufaktur", "Abacus", "Beispiel GmbH", "entitys", "Shopware"])
        XCTAssertEqual(vocabulary.replacements, [
            TermReplacement(spoken: "n acht n", written: "n8n"),
            TermReplacement(spoken: "Schenobel", written: "Channable"),
            TermReplacement(spoken: "Schenobl", written: "Channable"),
            TermReplacement(spoken: "Superbase", written: "Supabase"),
            TermReplacement(spoken: "ihren wegs", written: "INWX"),
        ])
        XCTAssertEqual(vocabulary.context, "Schaltwerk Digital ist eine E-Commerce-Agentur. Wir arbeiten mit Shopify und Shopware.")
    }

    func testEmptyOrForeignFileGivesNothing() {
        XCTAssertTrue(TeamVocabulary.parse("").isEmpty)
        XCTAssertTrue(TeamVocabulary.parse("# Notiz\n- Einkaufen\n- Milch").isEmpty)
    }

    func testHeadingNames() {
        XCTAssertEqual(TeamVocabulary.section(forHeading: "Eigennamen und Begriffe"), .terms)
        XCTAssertEqual(TeamVocabulary.section(forHeading: "Ersetzungen (gesprochen → geschrieben)"), .replacements)
        XCTAssertEqual(TeamVocabulary.section(forHeading: "KONTEXT für die KI-Modi"), .context)
        XCTAssertEqual(TeamVocabulary.section(forHeading: "Pflege"), .other)
    }

    func testAddingTermGoesToAppGroupAtEndOfSection() {
        let once = TeamVocabulary.adding(term: "Pickware", to: sample)
        let twice = TeamVocabulary.adding(term: "Billbee", to: once)
        XCTAssertEqual(TeamVocabulary.parse(twice).terms.suffix(2), ["Pickware", "Billbee"])
        XCTAssertEqual(twice.components(separatedBy: TeamVocabulary.addedInAppHeading).count, 2, "one group only")
        // Still before "## Ersetzungen", and the rest of the file is untouched.
        let pickware = twice.range(of: "- Pickware")!.lowerBound
        XCTAssertLessThan(pickware, twice.range(of: "## Ersetzungen")!.lowerBound)
        XCTAssertEqual(TeamVocabulary.parse(twice).replacements, TeamVocabulary.parse(sample).replacements)
        XCTAssertTrue(twice.hasPrefix("---\ntyp: wortschatz\n---"))
    }

    func testAddingKnownTermChangesNothing() {
        XCTAssertEqual(TeamVocabulary.adding(term: "velomanufaktur", to: sample), sample)
        XCTAssertEqual(TeamVocabulary.adding(term: "  ", to: sample), sample)
    }

    func testAddingReplacement() {
        let rule = TermReplacement(spoken: "Prevo", written: "Brevo")
        let updated = TeamVocabulary.adding(rule, to: sample)
        XCTAssertEqual(TeamVocabulary.parse(updated).replacements.last, rule)
        XCTAssertLessThan(updated.range(of: "- Prevo \u{2192} Brevo")!.lowerBound, updated.range(of: "## Kontext")!.lowerBound)
        XCTAssertEqual(TeamVocabulary.adding(TermReplacement(spoken: "superbase", written: "X"), to: sample), sample)
    }

    func testAddingCreatesMissingSection() {
        let updated = TeamVocabulary.adding(term: "Hetzner", to: "# Wortschatz\n\nNoch leer.\n")
        XCTAssertEqual(TeamVocabulary.parse(updated).terms, ["Hetzner"])
        XCTAssertTrue(updated.contains("## Begriffe"))
    }

    func testMergeWithPersonalSettings() {
        var personal = TextImprovementSettings()
        personal.customTerms = ["Erika Mustermann", "shopware"]
        personal.replacements = [TermReplacement(spoken: "Superbase", written: "Superbase GmbH")]
        let team = TeamVocabulary.parse(sample)

        let merged = personal.adding(team)
        XCTAssertEqual(merged.correctionTerms, ["Erika Mustermann", "shopware", "Velomanufaktur", "Abacus", "Beispiel GmbH", "entitys"])
        XCTAssertEqual(merged.allReplacements.first, personal.replacements.first)
        XCTAssertFalse(merged.allReplacements.contains(TermReplacement(spoken: "Superbase", written: "Supabase")), "personal rule wins")
        XCTAssertEqual(merged.context, team.context)

        personal.context = "Eigener Kontext"
        XCTAssertEqual(personal.adding(team).context, "Eigener Kontext")
    }

    func testTeamEntriesNeverReachTheSavedSettings() throws {
        let merged = TextImprovementSettings().adding(TeamVocabulary.parse(sample))
        let json = String(decoding: try JSONEncoder().encode(merged), as: UTF8.self)
        XCTAssertFalse(json.contains("Velomanufaktur"))
        XCTAssertFalse(json.contains("Channable"))
    }

    func testPromptOnlyNamesTeamTermsThatWereSaid() {
        var personal = TextImprovementSettings()
        personal.customTerms = ["Blackboat"]
        let merged = personal.adding(TeamVocabulary.parse(sample))
        let narrowed = merged.narrowingTeamTerms(to: "Die Daten für die Velomanufaktur kommen aus Channable.")
        XCTAssertEqual(narrowed.protectedTerms, ["Blackboat", "Velomanufaktur", "Channable"])

        let prompt = ModePrompts.textImprovement(narrowed)
        XCTAssertTrue(prompt.contains("Blackboat, Velomanufaktur, Channable"))
        XCTAssertFalse(prompt.contains("Beispiel GmbH"))
        XCTAssertTrue(prompt.contains("Kontext: Schaltwerk Digital"))
    }

    func testTeamVocabularyCorrectsTranscript() {
        let settings = TextImprovementSettings().adding(TeamVocabulary.parse(sample))
        let processor = TranscriptPostProcessor(
            customTerms: settings.correctionTerms,
            replacements: settings.allReplacements,
            removeFillerWords: false
        )
        XCTAssertEqual(
            processor.process("Die Daten der Felomanufaktur laufen über Schenobel nach Superbase."),
            "Die Daten der Velomanufaktur laufen über Channable nach Supabase."
        )
    }
}
