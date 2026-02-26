import XCTest
@testable import CoderIDE

@MainActor
final class PlanHistoryStoreTests: XCTestCase {
    private let key = "CoderIDE.planHistory"
    private var fileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("CoderIDE", isDirectory: true)
            .appendingPathComponent("planHistory.json")
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: fileURL)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    func testCreateAndReloadEntry() {
        let store = PlanHistoryStore()
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

        let reloaded = PlanHistoryStore()
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.id, entry.id)
    }

    func testDuplicateEntryCreatesNewId() {
        let store = PlanHistoryStore()
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
}
