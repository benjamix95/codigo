import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class ChatStoreDraftPersistenceTests: XCTestCase {

    private func makeStore(
        suiteName: String = "ChatStoreDraftPersistenceTests.\(UUID().uuidString)"
    ) -> (ChatStore, UserDefaults, String) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ChatStore(userDefaults: defaults)
        return (store, defaults, suiteName)
    }

    private func waitForPersistQueue() async {
        let exp = expectation(description: "persistQueue")
        ChatStore.persistQueue.async { exp.fulfill() }
        await fulfillment(of: [exp], timeout: 2)
    }

    // MARK: - Load Tests

    func testLoadDraftsRestoresPersistedDrafts() async {
        let suiteName = "ChatStoreDraftPersistenceTests.load.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let convId = UUID()
        let drafts: [String: String] = [convId.uuidString.lowercased(): "Ciao mondo"]
        let data = try! JSONEncoder().encode(drafts)
        defaults.set(data, forKey: "CoderIDE.draftTexts")

        let store = ChatStore(userDefaults: defaults)
        XCTAssertEqual(store.draftTexts[convId], "Ciao mondo")
    }

    func testLoadDraftsHandlesMissingData() {
        let (store, _, suiteName) = makeStore()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(store.draftTexts.isEmpty)
    }

    func testLoadDraftsHandlesCorruptData() {
        let suiteName = "ChatStoreDraftPersistenceTests.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("not valid json".utf8), forKey: "CoderIDE.draftTexts")

        let store = ChatStore(userDefaults: defaults)
        XCTAssertTrue(store.draftTexts.isEmpty, "Dati corrotti non devono causare crash")
    }

    func testLoadDraftsIgnoresInvalidUUIDs() async {
        let suiteName = "ChatStoreDraftPersistenceTests.invalidUUID.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let validId = UUID()
        let drafts: [String: String] = [
            validId.uuidString.lowercased(): "Testo valido",
            "not-a-uuid": "Testo invalido",
        ]
        let data = try! JSONEncoder().encode(drafts)
        defaults.set(data, forKey: "CoderIDE.draftTexts")

        let store = ChatStore(userDefaults: defaults)
        XCTAssertEqual(store.draftTexts.count, 1)
        XCTAssertEqual(store.draftTexts[validId], "Testo valido")
    }

    // MARK: - Save Tests

    func testSaveDraftsImmediatelyPersistsToDisk() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let convId = store.conversations.first!.id
        store.draftTexts[convId] = "Bozza di test"
        store.saveDraftsImmediately()
        await waitForPersistQueue()

        let data = defaults.data(forKey: "CoderIDE.draftTexts")
        XCTAssertNotNil(data, "I drafts devono essere persistiti su UserDefaults")

        let decoded = try! JSONDecoder().decode([String: String].self, from: data!)
        XCTAssertEqual(decoded[convId.uuidString.lowercased()], "Bozza di test")
    }

    func testSaveDraftsImmediatelyWithEmptyDrafts() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.draftTexts = [:]
        store.saveDraftsImmediately()
        await waitForPersistQueue()

        let data = defaults.data(forKey: "CoderIDE.draftTexts")
        XCTAssertNotNil(data)
        let decoded = try! JSONDecoder().decode([String: String].self, from: data!)
        XCTAssertTrue(decoded.isEmpty)
    }

    // MARK: - Delete Conversation Tests

    func testDeleteConversationRemovesDraft() async {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let convId = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)
        store.draftTexts[convId] = "Draft da eliminare"
        store.saveDraftsImmediately()
        await waitForPersistQueue()

        _ = store.deleteConversation(id: convId)
        XCTAssertNil(store.draftTexts[convId], "Il draft deve essere rimosso dalla memoria")
    }

    // MARK: - Round-trip Test

    func testDraftRoundTrip() async {
        let suiteName = "ChatStoreDraftPersistenceTests.roundtrip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store1 = ChatStore(userDefaults: defaults)
        let convId = store1.conversations.first!.id
        store1.draftTexts[convId] = "Messaggio in bozza"
        store1.saveDraftsImmediately()
        await waitForPersistQueue()

        let store2 = ChatStore(userDefaults: defaults)
        XCTAssertEqual(
            store2.draftTexts[convId],
            "Messaggio in bozza",
            "Il draft deve sopravvivere al riavvio dello store"
        )
    }
}
