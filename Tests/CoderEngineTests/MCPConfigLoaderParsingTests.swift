import XCTest
@testable import CoderEngine

final class MCPConfigLoaderParsingTests: XCTestCase {
    func testStrictParserParsesArgsEnvAndComments() throws {
        let toml = """
        [mcp_servers.coderide]
        command = "/usr/local/bin/coderide-mcp-server-rust" # inline comment
        args = ["--workspace", ".", "--mode", "strict"]
        env = { API_KEY = "abc", LOG_LEVEL = "debug" }
        """

        let servers = try MCPConfigLoader.parseCodexMCPConfigForTests(toml)
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers.first?.name, "coderide")
        XCTAssertEqual(servers.first?.command, "/usr/local/bin/coderide-mcp-server-rust")
        XCTAssertEqual(servers.first?.args, ["--workspace", ".", "--mode", "strict"])
        XCTAssertEqual(servers.first?.env["API_KEY"], "abc")
        XCTAssertEqual(servers.first?.env["LOG_LEVEL"], "debug")
    }

    func testStrictParserIncludesLineInErrorMessage() {
        let toml = """
        [mcp_servers.bad]
        command = "/bin/echo"
        args = invalid
        """

        XCTAssertThrowsError(try MCPConfigLoader.parseCodexMCPConfigForTests(toml)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("line 3"), "Unexpected error: \(message)")
            XCTAssertTrue(message.contains("args"), "Unexpected error: \(message)")
        }
    }

    func testDeduplicateKeepsSameNameAcrossDifferentSources() {
        let one = makeServer(source: "codex", origin: "toml", path: "/Users/dev/.codex/config.toml", name: "shared")
        let two = makeServer(source: "cursor", origin: "json", path: "/Users/dev/.cursor/mcp.json", name: "shared")

        let deduped = MCPConfigLoader.deduplicateDetectedServers([one, two])
        XCTAssertEqual(deduped.count, 2)
    }

    func testDeduplicateDropsExactIdentityDuplicate() {
        let one = makeServer(source: "codex", origin: "toml", path: "/Users/dev/.codex/config.toml", name: "dup")
        let two = makeServer(source: "codex", origin: "toml", path: "/Users/dev/.codex/config.toml", name: "dup")

        let deduped = MCPConfigLoader.deduplicateDetectedServers([one, two])
        XCTAssertEqual(deduped.count, 1)
    }

    private func makeServer(source: String, origin: String, path: String, name: String) -> MCPConfigLoader.DetectedServer {
        let identity = MCPServerIdentity.make(source: source, name: name, origin: origin, sourcePath: path)
        return MCPConfigLoader.DetectedServer(
            id: identity.stableIdentifier,
            identity: identity,
            legacyID: "\(source)-\(name)",
            name: name,
            command: "/bin/echo",
            args: [],
            env: [:],
            source: source
        )
    }
}
