import Foundation

extension UnifiedToolRuntime {
    func run(
        _ call: ToolCall,
        normalizedName: String,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        do {
            if context.policy.enableMCP,
               Self.shouldPreferRustAlias(for: normalizedName),
               MCPNativeToolRegistry.shared.hasTools(),
               preferredRustAliasRoute(for: normalizedName) == nil {
                throw ToolRuntimeError.mcpUnavailable(
                    "Rust MCP route required for '\(normalizedName)' but no native alias is registered"
                )
            }

            if context.policy.enableMCP,
               let aliasRoute = preferredRustAliasRoute(for: normalizedName) {
                return await executeNativeMCPTool(
                    functionName: normalizedName,
                    route: aliasRoute,
                    call: call,
                    context: context,
                    startDate: startDate
                )
            }

            try validate(call: call, normalizedName: normalizedName)

            return try await runValidatedDispatch(
                call,
                normalizedName: normalizedName,
                context: context,
                startDate: startDate
            )
        } catch let err as ToolRuntimeError {
            let isMCP = context.policy.enableMCP && (
                MCPNativeToolRegistry.shared.routing[normalizedName] != nil ||
                MCPNativeToolRegistry.shared.aliasRoute(for: normalizedName) != nil ||
                (Self.shouldPreferRustAlias(for: normalizedName) && MCPNativeToolRegistry.shared.hasTools()) ||
                canFallbackToMCP(toolName: normalizedName, call: call)
            )
            let mcpPayload = isMCP ? ["is_mcp": "true"] : [String: String]()
            return failure(
                err.localizedDescription,
                errorCode: err.errorCode,
                startDate: startDate,
                payload: mcpPayload
            )
        } catch {
            let isMCP = context.policy.enableMCP && (
                MCPNativeToolRegistry.shared.routing[normalizedName] != nil ||
                MCPNativeToolRegistry.shared.aliasRoute(for: normalizedName) != nil ||
                (Self.shouldPreferRustAlias(for: normalizedName) && MCPNativeToolRegistry.shared.hasTools()) ||
                canFallbackToMCP(toolName: normalizedName, call: call)
            )
            let mcpPayload = isMCP ? ["is_mcp": "true"] : [String: String]()
            return failure(
                error.localizedDescription,
                errorCode: "unknown",
                startDate: startDate,
                payload: mcpPayload
            )
        }
    }

    private func runValidatedDispatch(
        _ call: ToolCall,
        normalizedName: String,
        context: ToolExecutionContext,
        startDate: Date
    ) async throws -> ToolResult {
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
        case ReviewAuditToolName.securitySecrets,
             ReviewAuditToolName.securityDependencies,
             ReviewAuditToolName.securityPatterns,
             ReviewAuditToolName.securityDataflow,
             ReviewAuditToolName.securityAuthz,
             ReviewAuditToolName.securityCrypto,
             ReviewAuditToolName.securityDeserialization,
             ReviewAuditToolName.securitySurface,
             ReviewAuditToolName.securitySupplyChain,
             ReviewAuditToolName.bugDiffRisks,
             ReviewAuditToolName.bugTestGaps,
             ReviewAuditToolName.bugHotspots,
             ReviewAuditToolName.bugNilCrashPaths,
             ReviewAuditToolName.bugStateMachine,
             ReviewAuditToolName.bugConcurrency,
             ReviewAuditToolName.bugErrorHandling,
             ReviewAuditToolName.bugAPIContracts,
             ReviewAuditToolName.bugTestImpact,
             ReviewAuditToolName.bugDependencyDrift,
             ReviewAuditToolName.bugDiffSemantics,
             ReviewAuditToolName.runProfile,
             ReviewAuditToolName.correlateFindings,
             ReviewAuditToolName.verifyBundle,
             ReviewAuditToolName.explainFinding:
            return await executeAuditTool(
                name: normalizedName,
                call: call,
                context: context,
                startDate: startDate
            )
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
        case "parallel_apply":
            return try await executeParallelApply(call: call, context: context, startDate: startDate)
        case "regex_replace":
            return try executeRegexReplace(call: call, context: context, startDate: startDate)
        case "attempt_completion":
            return await executeAttemptCompletion(call: call, context: context, startDate: startDate)
        case "diagnostics":
            return await executeDiagnostics(call: call, context: context, startDate: startDate)
        case "rename_symbol":
            return await executeRenameSymbol(call: call, context: context, startDate: startDate)
        case "find_and_replace_all":
            return await executeFindAndReplaceAll(call: call, context: context, startDate: startDate)
        case "undo_edit":
            return await executeUndoEdit(call: call, context: context, startDate: startDate)
        case "run_single_test":
            return await executeRunSingleTest(call: call, context: context, startDate: startDate)
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
        case "semantic_search":
            return await executeSemanticSearch(call: call, context: context, startDate: startDate)
        case "search_health_check":
            return await executeSearchHealthCheck(call: call, context: context, startDate: startDate)
        case "read_lints":
            return await executeReadLints(call: call, context: context, startDate: startDate)
        case "debug_context":
            return await executeDebugContext(call: call, context: context, startDate: startDate)
        case "codebase_search", "find_symbol", "list_symbols", "find_references",
             "project_structure", "file_outline", "find_files", "codebase_stats",
             "dependency_graph", "list_types", "list_tests", "index_status", "reindex":
            return await executeIndexTool(
                name: normalizedName,
                call: call,
                context: context,
                startDate: startDate
            )
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
    }
}
