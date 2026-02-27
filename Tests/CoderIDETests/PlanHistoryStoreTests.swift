import XCTest
@testable import CoderIDE

@MainActor
final class PlanHistoryStoreTests: XCTestCase {
    private let key = "CoderIDE.planHistory"
    private let maxEntriesKey = planHistoryMaxEntriesPreferenceKey
    private let maxMarkdownKey = planHistoryMaxMarkdownLengthPreferenceKey
    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        suiteName = "PlanHistoryStoreTests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        let tmpDir = FileManager.default.temporaryDirectory
        fileURL = tmpDir.appendingPathComponent("planHistory-\(UUID().uuidString).json")
        isolatedDefaults.removeObject(forKey: key)
        isolatedDefaults.removeObject(forKey: maxEntriesKey)
        isolatedDefaults.removeObject(forKey: maxMarkdownKey)
        try? FileManager.default.removeItem(at: fileURL)
    }

    override func tearDown() {
        isolatedDefaults.removeObject(forKey: key)
        isolatedDefaults.removeObject(forKey: maxEntriesKey)
        isolatedDefaults.removeObject(forKey: maxMarkdownKey)
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: fileURL)
        fileURL = nil
        isolatedDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> PlanHistoryStore {
        PlanHistoryStore(userDefaults: isolatedDefaults, storageURL: fileURL)
    }

    func testCreateAndReloadEntry() {
        let store = makeStore()
        let convId = UUID()
        let entry = store.createEntry(
            conversationId: convId,
            contextId: nil,
            contextFolderPath: nil,
            title: "Plan A",
            markdown: "# Plan A",
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil
        )
        XCTAssertEqual(store.entries.count, 1)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.id, entry.id)
    }

    func testDuplicateEntryCreatesNewId() {
        let store = makeStore()
        let entry = store.createEntry(
            conversationId: UUID(),
            contextId: nil,
            contextFolderPath: nil,
            title: "Plan A",
            markdown: "# Plan A",
            options: [],
            chosenPath: "A",
            tags: ["tag"],
            sourceMessageId: UUID()
        )
        let duplicate = store.duplicateEntry(id: entry.id)
        XCTAssertNotNil(duplicate)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertNotEqual(duplicate?.id, entry.id)
        XCTAssertNil(duplicate?.sourceMessageId)
    }

    func testCreateEntryRespectsConfiguredMarkdownLimit() {
        isolatedDefaults.set(32_768, forKey: maxMarkdownKey)
        let store = makeStore()
        let longMarkdown = String(repeating: "A", count: 40_000)

        let entry = store.createEntry(
            conversationId: UUID(),
            contextId: nil,
            contextFolderPath: nil,
            title: "Long plan",
            markdown: longMarkdown,
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil
        )

        XCTAssertEqual(entry.markdown.count, 32_768)
    }

    func testApplyConfiguredLimitsTrimsExistingEntries() {
        isolatedDefaults.set(200, forKey: maxEntriesKey)
        isolatedDefaults.set(65_536, forKey: maxMarkdownKey)
        let store = makeStore()
        let longMarkdown = String(repeating: "B", count: 60_000)

        _ = store.createEntry(
            conversationId: UUID(),
            contextId: nil,
            contextFolderPath: nil,
            title: "Plan",
            markdown: longMarkdown,
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil
        )
        XCTAssertEqual(store.entries.first?.markdown.count, 60_000)

        isolatedDefaults.set(32_768, forKey: maxMarkdownKey)
        store.applyConfiguredLimits()

        XCTAssertEqual(store.entries.first?.markdown.count, 32_768)
    }

    func testFindLatestEntryForConversation() {
        let store = makeStore()
        let conversationA = UUID()
        let conversationB = UUID()

        _ = store.createEntry(
            conversationId: conversationA,
            contextId: nil,
            contextFolderPath: nil,
            title: "Plan A 1",
            markdown: "# Plan A 1",
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil
        )
        _ = store.createEntry(
            conversationId: conversationB,
            contextId: nil,
            contextFolderPath: nil,
            title: "Plan B",
            markdown: "# Plan B",
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil
        )
        let second = store.createEntry(
            conversationId: conversationA,
            contextId: nil,
            contextFolderPath: nil,
            title: "Plan A 2",
            markdown: "# Plan A 2",
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil
        )

        let latest = store.findLatestEntry(for: conversationA)
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.id, second.id)
        XCTAssertEqual(latest?.title, "Plan A 2")
    }

    func testFindLatestEntryForConversationReturnsNilWhenMissing() {
        let store = makeStore()
        let latest = store.findLatestEntry(for: UUID())
        XCTAssertNil(latest)
    }
}
