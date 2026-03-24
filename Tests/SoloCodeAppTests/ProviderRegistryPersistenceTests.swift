import XCTest
@testable import CoderEngine

/// Tests for ProviderRegistry persistence of last-used provider.
final class ProviderRegistryPersistenceTests: XCTestCase {
    private let key = "lastUsedProviderId"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testSelectedProviderIdWritesToUserDefaults() {
        let registry = ProviderRegistry()
        registry.selectedProviderId = "claude-cli"
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: key),
            "claude-cli"
        )
    }

    func testLastUsedProviderIdReadsFromUserDefaults() {
        UserDefaults.standard.set("gemini-cli", forKey: key)
        let registry = ProviderRegistry()
        XCTAssertEqual(registry.lastUsedProviderId, "gemini-cli")
    }

    func testNilSelectionDoesNotOverwriteDefaults() {
        UserDefaults.standard.set("codex-cli", forKey: key)
        let registry = ProviderRegistry()
        registry.selectedProviderId = nil
        // nil should NOT overwrite the stored value
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: key),
            "codex-cli"
        )
    }

    func testEmptySelectionDoesNotOverwriteDefaults() {
        UserDefaults.standard.set("codex-cli", forKey: key)
        let registry = ProviderRegistry()
        registry.selectedProviderId = ""
        // Empty string should NOT overwrite
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: key),
            "codex-cli"
        )
    }
}
