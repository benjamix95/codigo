import XCTest
@testable import CoderEngine

final class PerformanceAuditToolIntegrationTests: XCTestCase {
    private func makeTmpWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-audit-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func lastRawPayload(_ events: [StreamEvent]) -> [String: String]? {
        for event in events.reversed() {
            if case .raw(_, let payload) = event {
                return payload
            }
        }
        return nil
    }

    func testRegistryResolvesPerformanceAuditAliases() {
        let registry = CoderIDECanonicalToolRegistry.shared

        XCTAssertEqual(
            registry.record(forRuntimeName: "auditperfbottlenecks")?.runtimeName,
            ReviewAuditToolName.perfBottlenecks
        )
        XCTAssertEqual(
            registry.record(forRuntimeName: "auditperfuiresponsiveness")?.runtimeName,
            ReviewAuditToolName.perfUIResponsiveness
        )
        XCTAssertEqual(
            registry.record(forRuntimeName: "coderide_audit_perf_hot_paths")?.runtimeName,
            ReviewAuditToolName.perfHotPaths
        )
    }

    func testPerformanceAuditToolsAreReadOnlyForProviderPolicy() {
        XCTAssertTrue(
            ToolEnabledLLMProvider.isReadOnlyTool(
                toolName: ReviewAuditToolName.perfBottlenecks,
                args: [:]
            )
        )
        XCTAssertTrue(
            ToolEnabledLLMProvider.isReadOnlyTool(
                toolName: ReviewAuditToolName.perfStartup,
                args: [:]
            )
        )
    }

    func testSyntheticEventsMapPerformanceAuditTool() {
        XCTAssertTrue(IDEStateSyntheticEventFactory.knowsTool("coderide_audit_perf_bottlenecks"))

        let events = IDEStateSyntheticEventFactory.events(
            rawTool: "coderide_audit_perf_bottlenecks",
            arguments: [
                "path": "Sources",
                "scope_files": #"["Sources/Service.swift"]"#,
            ],
            metadata: [
                "tool": ReviewAuditToolName.perfBottlenecks,
                "mcp_tool": "coderide_audit_perf_bottlenecks",
                "status": "completed",
            ],
            status: "completed",
            failureDetail: nil
        )

        XCTAssertEqual(events.first?.type, ReviewAuditToolName.perfBottlenecks)
        XCTAssertEqual(events.first?.payload["path"], "Sources")
        XCTAssertEqual(events.first?.payload["scope_files"], #"["Sources/Service.swift"]"#)
        XCTAssertEqual(events.first?.payload["tool"], ReviewAuditToolName.perfBottlenecks)
    }

    func testUnifiedRuntimeExecutesPerformanceAuditTool() async throws {
        let workspace = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceDir = workspace.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try """
        func doWork() {
            DispatchQueue.main.sync {
                updateUI()
            }
        }
        """.write(
            to: sourceDir.appendingPathComponent("Service.swift"),
            atomically: true,
            encoding: .utf8
        )

        let call = ToolCall(
            id: UUID().uuidString,
            name: ReviewAuditToolName.perfBottlenecks,
            args: ["scope_files": #"["Sources/Service.swift"]"#],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let context = ToolExecutionContext(
            workspaceContext: WorkspaceContext(workspacePath: workspace),
            policy: ToolRuntimePolicy(enableMCP: false)
        )

        let events = await UnifiedToolRuntime().execute(call, context: context)
        let payload = lastRawPayload(events)

        XCTAssertEqual(payload?["status"], "completed")
        XCTAssertEqual(payload?["tool"], ReviewAuditToolName.perfBottlenecks)
        XCTAssertFalse((payload?["detail"] ?? "").contains("Unsupported tool"))
    }
}
