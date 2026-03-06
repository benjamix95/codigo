import Foundation

extension UnifiedToolRuntime {
    public func execute(_ call: ToolCall, context: ToolExecutionContext) async -> [StreamEvent] {
        let normalizedName = normalizeToolName(call.name)
        let policy = context.policy

        let exemptFromRoundBudget = Self.readOnlyFileToolsExemptFromRoundBudget.contains(normalizedName)

        // Budget enforcement (defense-in-depth — ToolEnabledLLMProvider also enforces)
        if !exemptFromRoundBudget, toolCallsInCurrentRound >= policy.maxToolCallsPerRound {
            return [.raw(type: "tool_execution_error", payload: [
                "tool_call_id": call.id,
                "tool": normalizedName,
                "title": "Tool budget exceeded",
                "detail": "Reached tool limit per round (\(policy.maxToolCallsPerRound))",
                "status": "failed",
                "error_code": "budget_exceeded"
            ])]
        }
        let exemptFromRepetitionLimit = Self.readOnlyFileToolsExemptFromRepetitionLimit.contains(normalizedName)
        let nameCount = toolCallCountByName[normalizedName, default: 0]
        if !exemptFromRepetitionLimit, nameCount >= policy.maxRepeatedSameToolPerRound {
            return [.raw(type: "tool_execution_error", payload: [
                "tool_call_id": call.id,
                "tool": normalizedName,
                "title": "Tool repetition limit",
                "detail": "Tool '\(normalizedName)' exceeded per-round limit (\(policy.maxRepeatedSameToolPerRound))",
                "status": "failed",
                "error_code": "repetition_exceeded"
            ])]
        }
        if !exemptFromRoundBudget {
            toolCallsInCurrentRound += 1
        }
        if !exemptFromRepetitionLimit {
            toolCallCountByName[normalizedName, default: 0] += 1
        }

        let start = Date()
        let basePayload = buildBasePayload(call: call, normalizedName: normalizedName)
        let startEventType = startEventTypeForTool(name: normalizedName, payload: basePayload)

        var events: [StreamEvent] = [.raw(type: startEventType, payload: basePayload)]
        let result = await run(call, normalizedName: normalizedName, context: context, startDate: start)

        var completedPayload = result.payload
        completedPayload["tool_call_id"] = call.id
        completedPayload["tool"] = normalizedName
        completedPayload["duration_ms"] = "\(result.durationMs)"
        let existingStatus = (completedPayload["status"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if result.ok {
            if existingStatus.isEmpty {
                completedPayload["status"] = "completed"
            }
        } else {
            completedPayload["status"] = "failed"
        }
        if let swarmId = call.swarmId, !swarmId.isEmpty {
            completedPayload["swarm_id"] = swarmId
            completedPayload["group_id"] = "swarm-\(swarmId)"
        }

        let eventType = eventTypeForTool(name: normalizedName, ok: result.ok, payload: completedPayload)
        events.append(.raw(type: eventType, payload: completedPayload))
        if completedPayload["is_mcp"] == "true" {
            events.append(
                contentsOf: Self.syntheticIDEStateEventsFromMCP(
                    call: call,
                    completedPayload: completedPayload
                )
            )
        }

        // Auto-reindex modified files so semantic search stays fresh
        if result.ok, UnifiedToolRuntime.fileChangingTools.contains(normalizedName) {
            await reindexModifiedFile(call: call, context: context)
        }

        return events
    }

    func run(
        _ call: ToolCall,
        normalizedName: String,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        do {
            try validate(call: call, normalizedName: normalizedName)

            switch normalizedName {
            case "read":
                return try executeRead(call: call, context: context, startDate: startDate)
            case _ where SubagentRole.fromToolName(normalizedName) != nil:
                return await executeSubagentCall(call: call, context: context, startDate: startDate)
            case "read_range":
                return try executeReadRange(call: call, context: context, startDate: startDate)
            case "list_dir":
                return try executeListDir(call: call, context: context, startDate: startDate)
            case "git_diff":
                return await executeGitDiff(call: call, context: context, startDate: startDate)
            case "search_symbols":
                return await executeSearchSymbols(call: call, context: context, startDate: startDate)
            case "run_tests":
                return await executeRunTests(call: call, context: context, startDate: startDate)
            case "build_project":
                return await executeBuildProject(call: call, context: context, startDate: startDate)
            case "list_processes":
                return await executeListProcesses(call: call, context: context, startDate: startDate)
            case "read_json":
                return try executeReadJSON(call: call, context: context, startDate: startDate)
            case "write_json":
                return try executeWriteJSON(call: call, context: context, startDate: startDate)
            case "workspace_stats":
                return await executeWorkspaceStats(call: call, context: context, startDate: startDate)
            case "dependency_audit":
                return await executeDependencyAudit(call: call, context: context, startDate: startDate)
            case "tail_log":
                return await executeTailLog(call: call, context: context, startDate: startDate)
            case "glob":
                return await executeGlob(call: call, context: context, startDate: startDate)
            case "grep":
                return await executeGrep(call: call, context: context, startDate: startDate)
            case "str_replace":
                return try executeStrReplace(call: call, context: context, startDate: startDate)
            case "create_file":
                return try executeCreateFile(call: call, context: context, startDate: startDate)
            case "edit", "write":
                // If old_string is present, behave like str_replace for backward compatibility
                if let oldStr = call.args["old_string"], !oldStr.isEmpty {
                    return try executeStrReplace(call: call, context: context, startDate: startDate)
                }
                return try executeWrite(call: call, context: context, startDate: startDate)
            case "bash":
                let command = call.args["command"] ?? ""
                return await runBash(
                    command: command,
                    cwd: context.workspaceContext.workspacePath,
                    startDate: startDate,
                    title: "Bash",
                    timeoutMs: context.policy.timeoutMs,
                    maxOutputBytes: context.policy.maxBashOutputBytes,
                    policy: context.policy
                )
            case "read_terminal":
                return await executeReadTerminal(call: call, startDate: startDate)
            case "web_search":
                return await executeWebSearch(call: call, context: context, startDate: startDate)
            case "web_fetch":
                return await executeWebFetch(call: call, context: context, startDate: startDate)
            case "browser_navigate":
                return await executeBrowserNavigate(call: call, startDate: startDate)
            case "browser_screenshot":
                return await executeBrowserScreenshot(call: call, startDate: startDate)
            case "browser_console_logs":
                return await executeBrowserConsoleLogs(call: call, startDate: startDate)
            case "browser_click":
                return await executeBrowserClick(call: call, startDate: startDate)
            case "browser_type":
                return await executeBrowserType(call: call, startDate: startDate)
            case "browser_evaluate_js":
                return await executeBrowserEvaluateJS(call: call, startDate: startDate)
            case "browser_get_content":
                return await executeBrowserGetContent(call: call, startDate: startDate)
            // New Cursor-style tools
            case "parallel_apply":
                return try await executeParallelApply(call: call, context: context, startDate: startDate)
            case "regex_replace":
                return try executeRegexReplace(call: call, context: context, startDate: startDate)
            case "attempt_completion":
                return await executeAttemptCompletion(call: call, context: context, startDate: startDate)
            case "diagnostics":
                return await executeDiagnostics(call: call, context: context, startDate: startDate)

            // New powerful tools
            case "rename_symbol":
                return await executeRenameSymbol(call: call, context: context, startDate: startDate)
            case "find_and_replace_all":
                return await executeFindAndReplaceAll(call: call, context: context, startDate: startDate)
            case "undo_edit":
                return await executeUndoEdit(call: call, context: context, startDate: startDate)
            case "run_single_test":
                return await executeRunSingleTest(call: call, context: context, startDate: startDate)

            // Debug tools
            case "debug_log":
                return await executeDebugLog(call: call, context: context, startDate: startDate)
            case "debug_query":
                return await executeDebugQuery(call: call, context: context, startDate: startDate)
            case "debug_session":
                return await executeDebugSession(call: call, context: context, startDate: startDate)
            case "debug_hypothesize":
                return await executeDebugHypothesize(call: call, context: context, startDate: startDate)
            case "debug_mark":
                return await executeDebugMark(call: call, context: context, startDate: startDate)
            case "debug_clean":
                return await executeDebugClean(call: call, context: context, startDate: startDate)
            case "debug_trace_analyze":
                return await executeDebugTraceAnalyze(call: call, context: context, startDate: startDate)
            case "debug_instrument":
                return await executeDebugInstrument(call: call, context: context, startDate: startDate)
            case "debug_timeline":
                return await executeDebugTimeline(call: call, context: context, startDate: startDate)
            case "debug_snapshot":
                return await executeDebugSnapshot(call: call, context: context, startDate: startDate)
            case "debug_test_check":
                return await executeDebugTestCheck(call: call, context: context, startDate: startDate)

            // Power tools
            case "apply_diff":
                return try executeApplyDiff(call: call, context: context, startDate: startDate)
            case "batch_read":
                return try executeBatchRead(call: call, context: context, startDate: startDate)
            case "diff_files":
                return await executeDiffFiles(call: call, context: context, startDate: startDate)
            case "git_status":
                return await executeGitStatus(call: call, context: context, startDate: startDate)
            case "git_show":
                return await executeGitShow(call: call, context: context, startDate: startDate)
            case "code_context":
                return await executeCodeContext(call: call, context: context, startDate: startDate)

            // Cursor-style semantic tools
            case "semantic_search":
                return await executeSemanticSearch(call: call, context: context, startDate: startDate)
            case "search_health_check":
                return await executeSearchHealthCheck(call: call, context: context, startDate: startDate)
            case "read_lints":
                return await executeReadLints(call: call, context: context, startDate: startDate)
            case "debug_context":
                return await executeDebugContext(call: call, context: context, startDate: startDate)

            // Codebase index tools (13 tools)
            case "codebase_search", "find_symbol", "list_symbols", "find_references",
                 "project_structure", "file_outline", "find_files", "codebase_stats",
                 "dependency_graph", "list_types", "list_tests", "index_status", "reindex":
                return await executeIndexTool(name: normalizedName, call: call, context: context, startDate: startDate)

            case "skill":
                return await executeSkill(call: call, context: context, startDate: startDate)
            case "mcp", "mcp_call":
                return await executeMCPCall(call: call, context: context, startDate: startDate)
            case "mcp_list_tools":
                return await executeMCPListTools(call: call, context: context, startDate: startDate)
            case "mcp_describe_tool":
                return await executeMCPDescribeTool(call: call, context: context, startDate: startDate)
            case "mcp_health":
                return await executeMCPHealth(call: call, context: context, startDate: startDate)
            case "mcp_list_servers":
                return await executeMCPListServers(context: context, startDate: startDate)
            case "mcp_reconnect":
                return await executeMCPReconnect(call: call, context: context, startDate: startDate)
            case "mcp_batch":
                return await executeMCPBatch(call: call, context: context, startDate: startDate)
            case "mcp_list_resources":
                return await executeMCPListResources(call: call, context: context, startDate: startDate)
            case "mcp_read_resource":
                return await executeMCPReadResource(call: call, context: context, startDate: startDate)
            case "mcp_subscribe":
                return await executeMCPSubscribe(call: call, context: context, startDate: startDate)
            case "mcp_list_prompts":
                return await executeMCPListPrompts(call: call, context: context, startDate: startDate)
            case "mcp_get_prompt":
                return await executeMCPGetPrompt(call: call, context: context, startDate: startDate)
            case "mcp_logs":
                return await executeMCPLogs(call: call, context: context, startDate: startDate)
            case "mcp_restart_server":
                return await executeMCPRestartServer(call: call, context: context, startDate: startDate)
            default:
                if context.policy.enableMCP {
                    if let route = MCPNativeToolRegistry.shared.routing[normalizedName] {
                        return await executeNativeMCPTool(
                            functionName: normalizedName,
                            route: route,
                            call: call,
                            context: context,
                            startDate: startDate
                        )
                    }
                    if canFallbackToMCP(toolName: normalizedName, call: call) {
                        return await executeMCPDirectToolFallback(
                            toolName: normalizedName,
                            call: call,
                            context: context,
                            startDate: startDate
                        )
                    }
                }
                throw ToolRuntimeError.validation("Unsupported tool: \(normalizedName)")
            }
        } catch let err as ToolRuntimeError {
            let isMCP = context.policy.enableMCP && (
                MCPNativeToolRegistry.shared.routing[normalizedName] != nil ||
                canFallbackToMCP(toolName: normalizedName, call: call)
            )
            let mcpPayload = isMCP ? ["is_mcp": "true"] : [String: String]()
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: mcpPayload)
        } catch {
            let isMCP = context.policy.enableMCP && (
                MCPNativeToolRegistry.shared.routing[normalizedName] != nil ||
                canFallbackToMCP(toolName: normalizedName, call: call)
            )
            let mcpPayload = isMCP ? ["is_mcp": "true"] : [String: String]()
            return failure(error.localizedDescription, errorCode: "unknown", startDate: startDate, payload: mcpPayload)
        }
    }

}
