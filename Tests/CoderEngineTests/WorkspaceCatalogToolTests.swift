import XCTest
@testable import CoderEngine

final class WorkspaceCatalogToolTests: XCTestCase {
    func testShellIsNotWorkspaceCatalog() {
        XCTAssertFalse(ProviderToolEventMapper.isWorkspaceCatalogTool("bash"))
        XCTAssertFalse(ProviderToolEventMapper.isWorkspaceCatalogTool("command_execution"))
    }

    func testCoreIdeToolsAreWorkspaceCatalog() {
        XCTAssertTrue(ProviderToolEventMapper.isWorkspaceCatalogTool("grep"))
        XCTAssertTrue(ProviderToolEventMapper.isWorkspaceCatalogTool("read"))
        XCTAssertTrue(ProviderToolEventMapper.isWorkspaceCatalogTool("coderide_grep"))
    }

    func testReviewAuditBughunterPrefixesAreWorkspaceCatalog() {
        XCTAssertTrue(ProviderToolEventMapper.isWorkspaceCatalogTool("review_start"))
        XCTAssertTrue(ProviderToolEventMapper.isWorkspaceCatalogTool("bughunter_start"))
        XCTAssertTrue(ProviderToolEventMapper.isWorkspaceCatalogTool("audit_security_secrets"))
        XCTAssertTrue(ProviderToolEventMapper.isWorkspaceCatalogTool("audit_perf_bottlenecks"))
        XCTAssertTrue(ProviderToolEventMapper.isWorkspaceCatalogTool("security_start"))
        XCTAssertTrue(ProviderToolEventMapper.isWorkspaceCatalogTool("coderide_plan_create"))
    }

    func testArbitraryNameIsNotWorkspaceCatalog() {
        XCTAssertFalse(ProviderToolEventMapper.isWorkspaceCatalogTool("firecrawl_scrape"))
        XCTAssertFalse(ProviderToolEventMapper.isWorkspaceCatalogTool("some_vendor_tool"))
    }

    func testIDEStateSyntheticEventFactoryKnowsRegistryDrivenSessionTools() {
        XCTAssertTrue(IDEStateSyntheticEventFactory.knowsTool("coderide_review_status"))
        XCTAssertTrue(IDEStateSyntheticEventFactory.knowsTool("security_findings"))
        XCTAssertTrue(IDEStateSyntheticEventFactory.knowsTool("bughunter_run_history"))
        XCTAssertTrue(IDEStateSyntheticEventFactory.knowsTool("coderide_audit_perf_memory"))
        XCTAssertTrue(IDEStateSyntheticEventFactory.knowsTool("plan_create"))
    }
}
