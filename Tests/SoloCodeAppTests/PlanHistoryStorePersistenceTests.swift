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

    func testBoardPersistedUpdatesLatestEntryForConversation() async throws {
        let store = makeStore()
        let conversationId = UUID()
        _ = store.createEntry(
            conversationId: conversationId,
            contextId: nil,
            contextFolderPath: tmpPlanDir.path,
            title: "Old entry",
            markdown: "# Old",
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil
        )
        let latest = store.createEntry(
            conversationId: conversationId,
            contextId: nil,
            contextFolderPath: tmpPlanDir.path,
            title: "Latest entry",
            markdown: "# Latest",
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil
        )

        let board = PlanBoard(
            goal: "Updated goal",
            options: [PlanOption(id: 1, title: "A", fullText: "## Todo\n- [ ] Updated")],
            chosenPath: "## Todo\n- [ ] Updated",
            steps: [],
            updatedAt: .now
        )
        NotificationCenter.default.post(
            name: .planBoardDidPersist,
            object: nil,
            userInfo: ["conversationId": conversationId, "board": board]
        )
        await Task.yield()

        let refreshedLatest = try XCTUnwrap(store.findEntry(id: latest.id))
        XCTAssertEqual(refreshedLatest.title, "Updated goal")
        XCTAssertEqual(refreshedLatest.chosenPath, "## Todo\n- [ ] Updated")
        XCTAssertEqual(refreshedLatest.options.count, 1)
    }

    func testBoardPersistedPrefersSelectedEntryWhenConversationHasMultipleSnapshots() async throws {
        let store = makeStore()
        let conversationId = UUID()
        let first = store.createEntry(
            conversationId: conversationId,
            contextId: nil,
            contextFolderPath: tmpPlanDir.path,
            title: "First entry",
            markdown: "# First",
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil
        )
        _ = store.createEntry(
            conversationId: conversationId,
            contextId: nil,
            contextFolderPath: tmpPlanDir.path,
            title: "Second entry",
            markdown: "# Second",
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil
        )
        store.setSelectedEntry(id: first.id, conversationId: conversationId)

        let board = PlanBoard(
            goal: "Selected goal",
            options: [],
            chosenPath: "## Todo\n- [ ] Selected",
            steps: [],
            updatedAt: .now
        )
        NotificationCenter.default.post(
            name: .planBoardDidPersist,
            object: nil,
            userInfo: ["conversationId": conversationId, "board": board]
        )
        await Task.yield()

        let refreshedFirst = try XCTUnwrap(store.findEntry(id: first.id))
        XCTAssertEqual(refreshedFirst.title, "Selected goal")
        XCTAssertEqual(refreshedFirst.chosenPath, "## Todo\n- [ ] Selected")
    }
}
