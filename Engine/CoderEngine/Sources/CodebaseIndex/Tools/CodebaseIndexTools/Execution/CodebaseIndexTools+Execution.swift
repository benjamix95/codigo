import Foundation

// MARK: - CodebaseIndexTools execution entrypoint

extension CodebaseIndexTools {
    /// Executes an index tool and returns StreamEvent values.
    func execute(
        toolName: String,
        args: [String: String],
        callId: String,
        workspacePaths: [URL],
        excludedPaths: [String] = []
    ) async -> [StreamEvent] {
        let startTime = Date()

        // Ensure index is built
        let status = await index.status()
        if status.status == .indexing {
            Self.logger.notice("execute(\(toolName, privacy: .public)): index is currently building, waiting...")
            let ready = await index.waitUntilReady(timeoutMs: 30_000)
            if !ready {
                Self.logger.warning("execute(\(toolName, privacy: .public)): timed out waiting for index")
            }
        } else if shouldPerformFullReindex(statusInfo: status, workspacePaths: workspacePaths) {
            Self.logger.info("execute(\(toolName, privacy: .public)): triggering full reindex")
            let _ = await index.indexWorkspace(paths: workspacePaths, excludedPaths: excludedPaths)
        }

        let result: ToolOutput
        switch toolName {
        case "codebase_search":
            result = await executeCodebaseSearch(args: args)
        case "find_symbol":
            result = await executeFindSymbol(args: args)
        case "list_symbols":
            result = await executeListSymbols(args: args)
        case "find_references":
            result = await executeFindReferences(args: args)
        case "project_structure":
            result = await executeProjectStructure(args: args)
        case "file_outline":
            result = await executeFileOutline(args: args)
        case "find_files":
            result = await executeFindFiles(args: args)
        case "codebase_stats":
            result = await executeCodebaseStats()
        case "dependency_graph":
            result = await executeDependencyGraph(args: args)
        case "list_types":
            result = await executeListTypes()
        case "list_tests":
            result = await executeListTests()
        case "index_status":
            result = await executeIndexStatus()
        case "reindex":
            result = await executeReindex(workspacePaths: workspacePaths, excludedPaths: excludedPaths)
        default:
            result = ToolOutput(
                ok: false,
                title: "Unknown tool",
                output: "Tool '\(toolName)' not found in codebase index"
            )
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Build started event
        var startedPayload: [String: String] = [
            "tool_call_id": callId,
            "tool": toolName,
            "status": "started",
            "title": result.title,
        ]
        if let query = args["query"], !query.isEmpty {
            startedPayload["query"] = query
        }

        // Build completed event
        var completedPayload: [String: String] = [
            "tool_call_id": callId,
            "tool": toolName,
            "status": result.ok ? "completed" : "failed",
            "title": result.title,
            "output": result.output,
            "duration_ms": "\(durationMs)",
        ]
        if let detail = result.detail {
            completedPayload["detail"] = detail
        }

        let eventType = result.ok ? "read_batch_completed" : "tool_execution_error"
        return [
            .raw(type: "mcp_tool_call", payload: startedPayload),
            .raw(type: eventType, payload: completedPayload),
        ]
    }
}
