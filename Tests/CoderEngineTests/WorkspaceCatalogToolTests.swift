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
    }

    func testArbitraryNameIsNotWorkspaceCatalog() {
        XCTAssertFalse(ProviderToolEventMapper.isWorkspaceCatalogTool("firecrawl_scrape"))
        XCTAssertFalse(ProviderToolEventMapper.isWorkspaceCatalogTool("some_vendor_tool"))
    }
}
