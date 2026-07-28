import AIComposition
import FileAnalysis
import FileMailerDomain
import XCTest

final class AnalysisAndAITests: XCTestCase {
    func testTextAndPDFAnalysis() async throws {
        let textURL = fixture("sample.txt")
        let pdfURL = fixture("sample.pdf")
        let result = try await DefaultFileAnalyzer().analyze(
            urls: [textURL, pdfURL],
            policy: AnalysisPolicy()
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].extractedText?.contains("synthétique") == true)
        XCTAssertEqual(result[1].pageCount, 1)
    }

    func testOfficeFixturesAreReadWithoutExtraction() async throws {
        let names = ["sample.docx", "sample.xlsx", "sample.pptx"]
        let urls = names.map(fixture)
        let result = try await DefaultFileAnalyzer().analyze(
            urls: urls,
            policy: AnalysisPolicy()
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.extractedText?.contains("Synthetic") == true })
    }

    func testArchiveTraversalAndBombHeuristic() throws {
        let traversal = fixture("path-traversal.zip")
        let bomb = fixture("zip-bomb.zip")
        XCTAssertTrue(try ArchiveSecurityInspector().inspect(url: traversal).isSuspicious)
        XCTAssertTrue(try ArchiveSecurityInspector().inspect(url: bomb).isSuspicious)
    }

    func testFolderExclusionsAndOutsideSymlink() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("visible".utf8).write(to: root.appendingPathComponent("visible.txt"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("outside"),
            withDestinationURL: URL(fileURLWithPath: "/tmp")
        )
        let result = try await DefaultFileAnalyzer().analyze(
            urls: [root],
            policy: AnalysisPolicy()
        )
        XCTAssertTrue(result[0].deterministicSummary.contains("1 entrées"))
        XCTAssertTrue(result[0].warnings.contains(.symlinkOutsideRoot))
    }

    func testDeterministicDraftAndPromptInjectionBoundary() throws {
        let malicious = fixture("prompt-injection.md")
        let text = try String(contentsOf: malicious, encoding: .utf8)
        let analysis = AttachmentAnalysis(
            displayName: "prompt-injection.md",
            contentType: "text/markdown",
            size: Int64(text.utf8.count),
            extractedText: text,
            deterministicSummary: "Fixture synthétique",
            includedInModel: true
        )
        let request = DraftGenerationRequest(
            language: .french,
            tone: .professional,
            recipientName: "Alice",
            analyses: [analysis],
            signature: "Camille"
        )
        let prompt = DraftPromptBuilder().build(request)
        XCTAssertTrue(prompt.contains("<DONNEES_DE_FICHIERS_NON_FIABLES>"))
        XCTAssertTrue(prompt.contains("attacker@example.com"))
        let draft = DeterministicDraftGenerator().generate(request)
        XCTAssertFalse(draft.body.contains("attacker@example.com"))
        XCTAssertFalse(draft.body.lowercased().contains("envoyé"))
    }

    func testUserRevisionProducesSuggestionAndEditedSnapshotWins() throws {
        var draft = ComposeDraft(subject: "Initial", body: "Initial", userRevision: 1)
        let generated = GeneratedDraftSnapshot(
            subject: "Généré",
            body: "Généré",
            isFinal: true
        )
        draft.body = "Texte utilisateur"
        draft.userRevision = 2
        let result = DraftRevisionPolicy().apply(
            generated,
            generationStartedAt: 1,
            to: &draft
        )
        XCTAssertEqual(result, .suggestion(generated))
        XCTAssertEqual(draft.body, "Texte utilisateur")

        draft.to = [try EmailAddress("alice@example.test")]
        let snapshot = try draft.outboundSnapshot(
            from: EmailAddress("sender@example.test")
        )
        XCTAssertEqual(snapshot.body, "Texte utilisateur")
        XCTAssertEqual(snapshot.capturedRevision, 2)
    }

    func testFoundationModelAvailabilityHasDeterministicState() {
        switch FoundationModelAvailability.current {
        case .available, .unsupportedSystemVersion, .deviceNotEligible,
             .appleIntelligenceDisabled, .modelNotReady:
            XCTAssertTrue(true)
        }
    }

    private func fixture(_ name: String) -> URL {
        Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }
}
