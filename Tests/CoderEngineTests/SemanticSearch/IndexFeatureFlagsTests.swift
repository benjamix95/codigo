import XCTest
@testable import CoderEngine

final class IndexFeatureFlagsTests: XCTestCase {

    // MARK: - Vector Search

    func testVectorSearchEnabledDefaultsToTrue() {
        // Remove any existing override so we test the default.
        UserDefaults.standard.removeObject(forKey: "vector_search_enabled")
        // Clear env override if present (we can't unset env in process,
        // so skip if env is explicitly set).
        guard ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_VECTOR_SEARCH"] == nil else {
            return // env override present, can't test UserDefaults default
        }
        XCTAssertTrue(IndexFeatureFlags.vectorSearchEnabled, "Vector search should default to true")
    }

    func testVectorSearchReadsUserDefaults() {
        guard ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_VECTOR_SEARCH"] == nil else {
            return
        }
        UserDefaults.standard.set(false, forKey: "vector_search_enabled")
        XCTAssertFalse(IndexFeatureFlags.vectorSearchEnabled)

        UserDefaults.standard.set(true, forKey: "vector_search_enabled")
        XCTAssertTrue(IndexFeatureFlags.vectorSearchEnabled)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "vector_search_enabled")
    }

    // MARK: - Trigram Index

    func testTrigramIndexEnabledDefaultsToTrue() {
        UserDefaults.standard.removeObject(forKey: "trigram_index_enabled")
        guard ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_TRIGRAM_INDEX"] == nil else {
            return
        }
        XCTAssertTrue(IndexFeatureFlags.trigramIndexEnabled, "Trigram index should default to true")
    }

    func testTrigramIndexReadsUserDefaults() {
        guard ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_TRIGRAM_INDEX"] == nil else {
            return
        }
        UserDefaults.standard.set(false, forKey: "trigram_index_enabled")
        XCTAssertFalse(IndexFeatureFlags.trigramIndexEnabled)

        UserDefaults.standard.set(true, forKey: "trigram_index_enabled")
        XCTAssertTrue(IndexFeatureFlags.trigramIndexEnabled)

        UserDefaults.standard.removeObject(forKey: "trigram_index_enabled")
    }

    // MARK: - Respect Gitignore

    func testRespectGitignoreDefaultsToTrue() {
        UserDefaults.standard.removeObject(forKey: "codebase_index_respect_gitignore")
        XCTAssertTrue(IndexFeatureFlags.respectGitignore, "Respect gitignore should default to true")
    }

    func testRespectGitignoreReadsUserDefaults() {
        UserDefaults.standard.set(false, forKey: "codebase_index_respect_gitignore")
        XCTAssertFalse(IndexFeatureFlags.respectGitignore)

        UserDefaults.standard.set(true, forKey: "codebase_index_respect_gitignore")
        XCTAssertTrue(IndexFeatureFlags.respectGitignore)

        UserDefaults.standard.removeObject(forKey: "codebase_index_respect_gitignore")
    }
}
