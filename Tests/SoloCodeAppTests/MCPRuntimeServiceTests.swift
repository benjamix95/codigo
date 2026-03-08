import CoderEngine
import XCTest
@testable import CoderIDE

final class MCPRuntimeServiceTests: XCTestCase {
    func testBuildRuntimeUsesSharedMCPSessionManager() async {
        let runtime = ProviderFactory.buildRuntime(
            executionController: nil,
            executionScope: .agent
        )
        let runtimeManager = await runtime.mcpSessions

        XCTAssertEqual(
            ObjectIdentifier(runtimeManager),
            ObjectIdentifier(MCPRuntimeService.sharedSessionManager)
        )
    }

    func testSettingsRestartUsesSharedMCPSessionManager() {
        XCTAssertEqual(
            ObjectIdentifier(MCPServerControlService.sessionManager),
            ObjectIdentifier(MCPRuntimeService.sharedSessionManager)
        )
    }
}
