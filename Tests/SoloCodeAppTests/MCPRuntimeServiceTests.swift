import CoderEngine
import XCTest
@testable import CoderIDE

final class MCPRuntimeServiceTests: XCTestCase {
    func testRuntimeServiceUsesGlobalSharedMCPSessionManager() {
        XCTAssertEqual(
            ObjectIdentifier(MCPRuntimeService.sharedSessionManager),
            ObjectIdentifier(MCPSessionManager.shared)
        )
    }

    func testBuildRuntimeUsesSharedMCPSessionManager() async {
        let runtime = ProviderFactory.buildRuntime(
            executionController: nil,
            executionScope: .agent
        )
        let runtimeManager = await runtime.mcpSessions

        XCTAssertEqual(
            ObjectIdentifier(runtimeManager),
            ObjectIdentifier(MCPSessionManager.shared)
        )
    }

    func testSettingsRestartUsesSharedMCPSessionManager() {
        XCTAssertEqual(
            ObjectIdentifier(MCPServerControlService.sessionManager),
            ObjectIdentifier(MCPSessionManager.shared)
        )
    }
}
