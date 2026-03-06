import XCTest
@testable import CoderEngine

final class MCPSessionManagerToolCacheTests: XCTestCase {
    func testBypassesToolCacheForCoderideServerByName() async {
        let manager = MCPSessionManager()
        let server = MCPConfigLoader.DetectedServer(
            id: "coderide",
            identity: .make(source: "codex", name: "coderide", origin: "codex"),
            name: "coderide",
            command: "/tmp/coderide-mcp-server",
            args: ["--workspace", "."],
            env: [:],
            source: "Codex"
        )

        let result = await manager.shouldBypassToolCache(for: server)
        XCTAssertTrue(result)
    }

    func testDoesNotBypassToolCacheForNonCoderideServer() async {
        let manager = MCPSessionManager()
        let server = MCPConfigLoader.DetectedServer(
            id: "docs",
            identity: .make(source: "codex", name: "docs", origin: "codex"),
            name: "docs",
            command: "/tmp/docs-server",
            args: [],
            env: [:],
            source: "Codex"
        )

        let result = await manager.shouldBypassToolCache(for: server)
        XCTAssertFalse(result)
    }
}
