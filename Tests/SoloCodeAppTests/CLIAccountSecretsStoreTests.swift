import XCTest
import Security
@testable import CoderIDE

final class CLIAccountSecretsStoreTests: XCTestCase {
    private let store = CLIAccountSecretsStore()
    private var testAccountIds: [UUID] = []

    override func tearDown() {
        for id in testAccountIds {
            store.deleteSecret(for: id)
        }
        testAccountIds.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeAccountId() -> UUID {
        let id = UUID()
        testAccountIds.append(id)
        return id
    }

    // MARK: - Basic CRUD

    func testSetAndRetrieveSecret() {
        let id = makeAccountId()
        store.setSecret("test-api-key-123", for: id)

        let retrieved = store.secret(for: id)
        XCTAssertEqual(retrieved, "test-api-key-123")
    }

    func testDeleteSecret() {
        let id = makeAccountId()
        store.setSecret("to-be-deleted", for: id)
        store.deleteSecret(for: id)

        let retrieved = store.secret(for: id)
        XCTAssertNil(retrieved)
    }

    func testSecretForNonexistentAccountReturnsNil() {
        let id = makeAccountId()
        XCTAssertNil(store.secret(for: id))
    }

    // MARK: - Atomic Update (SecItemUpdate path)

    func testSetSecretUpdatesExistingValueAtomically() {
        let id = makeAccountId()

        store.setSecret("original-value", for: id)
        XCTAssertEqual(store.secret(for: id), "original-value")

        // Second call should use SecItemUpdate path (not delete+add).
        store.setSecret("updated-value", for: id)
        XCTAssertEqual(store.secret(for: id), "updated-value")
    }

    func testSetSecretMultipleTimesAlwaysReturnsLatest() {
        let id = makeAccountId()

        for i in 0..<5 {
            store.setSecret("value-\(i)", for: id)
        }

        XCTAssertEqual(store.secret(for: id), "value-4")
    }

    // MARK: - Isolation between accounts

    func testSecretsAreIsolatedBetweenAccounts() {
        let id1 = makeAccountId()
        let id2 = makeAccountId()

        store.setSecret("secret-for-1", for: id1)
        store.setSecret("secret-for-2", for: id2)

        XCTAssertEqual(store.secret(for: id1), "secret-for-1")
        XCTAssertEqual(store.secret(for: id2), "secret-for-2")
    }

    func testDeleteOneAccountDoesNotAffectOther() {
        let id1 = makeAccountId()
        let id2 = makeAccountId()

        store.setSecret("keep-this", for: id1)
        store.setSecret("delete-this", for: id2)
        store.deleteSecret(for: id2)

        XCTAssertEqual(store.secret(for: id1), "keep-this")
        XCTAssertNil(store.secret(for: id2))
    }

    // MARK: - Edge cases

    func testSetEmptyStringSecret() {
        let id = makeAccountId()
        store.setSecret("", for: id)
        // Empty string becomes empty Data — Keychain stores it but we treat it as nil.
        let retrieved = store.secret(for: id)
        XCTAssertNil(retrieved, "Empty secrets should be treated as absent")
    }

    func testSetSecretWithUnicodeCharacters() {
        let id = makeAccountId()
        let unicodeSecret = "🔑clé-secrète-日本語"
        store.setSecret(unicodeSecret, for: id)

        XCTAssertEqual(store.secret(for: id), unicodeSecret)
    }

    func testDeleteNonexistentSecretDoesNotCrash() {
        let id = makeAccountId()
        // Should not throw or crash.
        store.deleteSecret(for: id)
        store.deleteSecret(for: id)
    }
}
