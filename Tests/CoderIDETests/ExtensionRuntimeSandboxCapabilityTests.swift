import XCTest
@testable import CoderIDE

final class ExtensionRuntimeSandboxCapabilityTests: XCTestCase {
    func testReadOnlyToolsExcludeMutatingDebugTools() throws {
        let sandbox = ExtensionRuntimeSandbox(
            allowedCapabilities: [.readOnlyTools, .writeWorkspace]
        )
        let manifest = makeManifest(capabilities: [.readOnlyTools])
        let granted = try sandbox.validate(manifest: manifest, currentIDEVersion: "1.0.0")

        let tools = sandbox.effectiveTools(for: manifest, grantedCapabilities: granted)

        XCTAssertFalse(tools.contains("debug_mark"))
        XCTAssertFalse(tools.contains("debug_instrument"))
        XCTAssertFalse(tools.contains("debug_clean"))
    }

    func testWriteWorkspaceIncludesMutatingDebugTools() throws {
        let sandbox = ExtensionRuntimeSandbox(
            allowedCapabilities: [.readOnlyTools, .writeWorkspace]
        )
        let manifest = makeManifest(capabilities: [.writeWorkspace])
        let granted = try sandbox.validate(manifest: manifest, currentIDEVersion: "1.0.0")

        let tools = sandbox.effectiveTools(for: manifest, grantedCapabilities: granted)

        XCTAssertTrue(tools.contains("debug_mark"))
        XCTAssertTrue(tools.contains("debug_instrument"))
        XCTAssertTrue(tools.contains("debug_clean"))
    }

    private func makeManifest(capabilities: [ExtensionCapability]) -> ExtensionManifest {
        ExtensionManifest(
            id: "com.codigo.extensions.capability-test",
            name: "Capability Test",
            version: "1.0.0",
            entryPoint: "Plugin",
            capabilities: capabilities,
            exposedTools: []
        )
    }
}
