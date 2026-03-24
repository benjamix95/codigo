import XCTest
@testable import CoderIDE

final class ProviderFactoryConfigFromDefaultsTests: XCTestCase {
    private let testSuiteName = "ProviderFactoryConfigFromDefaultsTests"
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: testSuiteName)!
        // Clear all keys before each test
        testDefaults.removePersistentDomain(forName: testSuiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil
        super.tearDown()
    }

    func testDefaultValuesWhenNoKeysSet() {
        let config = ProviderFactoryConfig.fromUserDefaults(testDefaults)

        XCTAssertEqual(config.openaiApiKey, "")
        XCTAssertEqual(config.openaiModel, "gpt-4o-mini")
        XCTAssertEqual(config.anthropicModel, "claude-sonnet-4-6")
        XCTAssertEqual(config.googleModel, "gemini-2.5-pro")
        XCTAssertEqual(config.minimaxModel, "MiniMax-M2.5")
        XCTAssertEqual(config.grokModel, "grok-4-1-fast-reasoning")
        XCTAssertEqual(config.codexSandbox, "workspace-write")
        XCTAssertEqual(config.codexAskForApproval, "never")
        XCTAssertTrue(config.codexFastMode)
        XCTAssertEqual(config.planModeBackend, "codex")
        XCTAssertEqual(config.swarmOrchestrator, "auto")
        XCTAssertFalse(config.globalYolo)
        XCTAssertEqual(config.codeReviewPartitions, 3)
        XCTAssertEqual(config.codeReviewMaxRounds, 3)
        XCTAssertTrue(config.unifiedToolRuntimeEnabled)
        XCTAssertTrue(config.agentsHardBlockEnabled)
        XCTAssertTrue(config.mcpEditEnforcementEnabled)
        XCTAssertEqual(config.webSearchProvider, "duckduckgo")
        XCTAssertEqual(config.claudeModel, "claude-sonnet-4-6")
    }

    func testReadsCustomValuesFromUserDefaults() {
        testDefaults.set("sk-test-key", forKey: "openai_api_key")
        testDefaults.set("gpt-4o", forKey: "openai_model")
        testDefaults.set("sk-ant-test", forKey: "anthropic_api_key")
        testDefaults.set(true, forKey: "global_yolo")
        testDefaults.set(false, forKey: "codex_fast_mode")
        testDefaults.set("brave", forKey: "web_search_provider")
        testDefaults.set("BSA-test", forKey: "brave_search_api_key")
        testDefaults.set(5, forKey: "code_review_partitions")

        let config = ProviderFactoryConfig.fromUserDefaults(testDefaults)

        XCTAssertEqual(config.openaiApiKey, "sk-test-key")
        XCTAssertEqual(config.openaiModel, "gpt-4o")
        XCTAssertEqual(config.anthropicApiKey, "sk-ant-test")
        XCTAssertTrue(config.globalYolo)
        XCTAssertFalse(config.codexFastMode)
        XCTAssertEqual(config.webSearchProvider, "brave")
        XCTAssertEqual(config.braveSearchApiKey, "BSA-test")
        XCTAssertEqual(config.codeReviewPartitions, 5)
    }

    func testBoolDefaultsTrueWhenKeyNotSet() {
        // These keys default to true when not set in UserDefaults
        let config = ProviderFactoryConfig.fromUserDefaults(testDefaults)

        XCTAssertTrue(config.codexFastMode, "codexFastMode should default to true")
        XCTAssertTrue(config.unifiedToolRuntimeEnabled, "unifiedToolRuntimeEnabled should default to true")
        XCTAssertTrue(config.agentsHardBlockEnabled, "agentsHardBlockEnabled should default to true")
        XCTAssertTrue(config.mcpEditEnforcementEnabled, "mcpEditEnforcementEnabled should default to true")
    }

    func testBoolDefaultsTrueCanBeSetToFalse() {
        testDefaults.set(false, forKey: "codex_fast_mode")
        testDefaults.set(false, forKey: "unified_tool_runtime_enabled")
        testDefaults.set(false, forKey: "agents_hard_block_enabled")
        testDefaults.set(false, forKey: "mcp_edit_enforcement_enabled")

        let config = ProviderFactoryConfig.fromUserDefaults(testDefaults)

        XCTAssertFalse(config.codexFastMode)
        XCTAssertFalse(config.unifiedToolRuntimeEnabled)
        XCTAssertFalse(config.agentsHardBlockEnabled)
        XCTAssertFalse(config.mcpEditEnforcementEnabled)
    }

    func testIntegerDefaultsWhenKeyNotSet() {
        let config = ProviderFactoryConfig.fromUserDefaults(testDefaults)

        XCTAssertEqual(config.codeReviewPartitions, 3)
        XCTAssertEqual(config.codeReviewMaxRounds, 3)
    }
}
