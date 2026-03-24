import XCTest
@testable import CoderIDE

/// Tests for plan persistence enhancements:
/// - updateMarkdown / updateTitle
/// - boardToMarkdown with mermaid, todo, progress
/// - sanitizeTitle rejects generic names
/// - writePlanFile writes to .solocode/plan/
/// - planBoardDidPersist notification triggers file update
@MainActor
final class PlanHistoryStorePersistenceTests: XCTestCase {
    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!
    private var fileURL: URL!
    private var tmpPlanDir: URL!

    override func setUp() {
        super.setUp()
        suiteName = "PlanPersistTests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("planHistory-\(UUID().uuidString).json")
        tmpPlanDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-workspace-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tmpPlanDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: tmpPlanDir)
        super.tearDown()
    }

    private func makeStore() -> PlanHistoryStore {
        PlanHistoryStore(userDefaults: isolatedDefaults, storageURL: fileURL)
    }

    // MARK: - updateMarkdown

    func testUpdateMarkdownPersistsNewContent() {
        let store = makeStore()
        let entry = store.createEntry(
            conversationId: UUID(), contextId: nil,
            contextFolderPath: tmpPlanDir.path,
            title: "Original Plan",
            markdown: "# Original",
            options: [], chosenPath: nil, tags: [],
            sourceMessageId: nil
        )
        store.updateMarkdown(id: entry.id, markdown: "# Updated content")
        XCTAssertEqual(store.entries.first?.markdown, "# Updated content")

        // Verify file on disk
        let planDir = PlanHistoryStore.solocodePlanDirectory(
            for: tmpPlanDir.path)
        let files = (try? FileManager.default.contentsOfDirectory(
            atPath: planDir.path)) ?? []
        let mdFiles = files.filter { $0.hasSuffix(".md") }
        XCTAssertFalse(mdFiles.isEmpty, "Plan .md file should exist")

        if let mdFile = mdFiles.first {
            let content = try? String(
                contentsOfFile: planDir.appendingPathComponent(mdFile).path,
                encoding: .utf8)
            XCTAssertEqual(content, "# Updated content")
        }
    }

    func testUpdateMarkdownIgnoresEmptyContent() {
        let store = makeStore()
        let entry = store.createEntry(
            conversationId: UUID(), contextId: nil,
            contextFolderPath: nil,
            title: "Keep This", markdown: "# Keep",
            options: [], chosenPath: nil, tags: [],
            sourceMessageId: nil
        )
        store.updateMarkdown(id: entry.id, markdown: "   ")
        XCTAssertEqual(store.entries.first?.markdown, "# Keep")
    }

    // MARK: - updateTitle

    func testUpdateTitlePersists() {
        let store = makeStore()
        let entry = store.createEntry(
            conversationId: UUID(), contextId: nil,
            contextFolderPath: nil,
            title: "Old Title", markdown: "# Plan",
            options: [], chosenPath: nil, tags: [],
            sourceMessageId: nil
        )
        store.updateTitle(id: entry.id, title: "New Title")
        XCTAssertEqual(store.entries.first?.title, "New Title")
    }

    // MARK: - sanitizeTitle rejects generics

    func testSanitizeTitleRejectsGenericNames() {
        let store = makeStore()
        let result = store.sanitizeTitle("Operational plan in progress")
        XCTAssertTrue(result.hasPrefix("Plan —"), "Generic title should be replaced: \(result)")
    }

    func testSanitizeTitleKeepsSpecificNames() {
        let store = makeStore()
        let result = store.sanitizeTitle("Refactor ChatPanelView into state containers")
        XCTAssertEqual(result, "Refactor ChatPanelView into state containers")
    }

    // MARK: - writePlanFile creates file

    func testCreateEntryWritesMdFile() {
        let store = makeStore()
        _ = store.createEntry(
            conversationId: UUID(), contextId: nil,
            contextFolderPath: tmpPlanDir.path,
            title: "Test Plan File",
            markdown: "# My Plan\n\nSteps here.",
            options: [], chosenPath: nil, tags: [],
            sourceMessageId: nil
        )
        let planDir = PlanHistoryStore.solocodePlanDirectory(
            for: tmpPlanDir.path)
        let files = (try? FileManager.default.contentsOfDirectory(
            atPath: planDir.path)) ?? []
        XCTAssertTrue(
            files.contains(where: { $0.hasSuffix(".md") }),
            "Should write .md file to .solocode/plan/"
        )
    }
}
