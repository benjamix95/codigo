import XCTest
@testable import CoderEngine

final class CoderIDECanonicalToolRegistryTests: XCTestCase {
    func testRegistryExposesCanonicalRuntimeNameForMCPTool() {
        XCTAssertEqual(
            CoderIDECanonicalToolRegistry.shared.runtimeName(forMCPName: "coderide_debug_set_phase"),
            "debug_set_phase"
        )
    }

    func testRegistryResolvesLegacyAliases() {
        let registry = CoderIDECanonicalToolRegistry.shared
        XCTAssertEqual(
            registry.record(forRuntimeName: "planrequestuserinput")?.runtimeName,
            "plan_request_user_input"
        )
        XCTAssertEqual(
            registry.record(forRuntimeName: "subagent_security_auditor")?.runtimeName,
            "subagent_securityAuditor"
        )
    }

    func testRegistryProvidesCapabilityScopedTools() {
        let debugTools = CoderIDECanonicalToolRegistry.shared.toolNames(for: .debug)
        XCTAssertTrue(debugTools.contains("activate_debug_mode"))
        XCTAssertTrue(debugTools.contains("debug_session"))

        let subagentTools = CoderIDECanonicalToolRegistry.shared.toolNames(for: .subagent)
        XCTAssertTrue(subagentTools.contains("subagent_debugger"))
        XCTAssertTrue(subagentTools.contains("subagent_explorer"))
    }

    func testRegistryTracksMutatingAndFirstRoundExemptSets() {
        let registry = CoderIDECanonicalToolRegistry.shared
        XCTAssertTrue(registry.mutatingRuntimeToolNames.contains("write"))
        XCTAssertFalse(registry.mutatingRuntimeToolNames.contains("read"))
        XCTAssertTrue(registry.firstRoundExemptRuntimeToolNames.contains("activate_debug_mode"))
        XCTAssertTrue(registry.firstRoundExemptRuntimeToolNames.contains("plan_request_user_input"))
    }

    func testRegistryProvidesSubagentProviderProfiles() {
        let registry = CoderIDECanonicalToolRegistry.shared
        XCTAssertEqual(registry.knownSubagentProviderIDs, ["claude", "codex", "gemini"])

        let codex = registry.providerCapabilityEntry(for: "codex")
        XCTAssertTrue(codex.supportsReadonlySubagent)
        XCTAssertTrue(codex.supportsWriteSubagent)
        XCTAssertTrue(codex.supportsWorkspaceSandbox)

        let claude = registry.providerCapabilityEntry(for: "claude")
        XCTAssertTrue(claude.supportsReadonlySubagent)
        XCTAssertFalse(claude.supportsWriteSubagent)

        let unknown = registry.providerCapabilityEntry(for: "unknown")
        XCTAssertFalse(unknown.supportsReadonlySubagent)
        XCTAssertFalse(unknown.supportsWriteSubagent)
    }
}
