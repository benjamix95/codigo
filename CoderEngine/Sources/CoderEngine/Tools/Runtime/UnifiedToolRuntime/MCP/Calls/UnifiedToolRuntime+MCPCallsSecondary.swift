import Foundation
import os

extension UnifiedToolRuntime {
    func executeMCPHealth(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server

        let metrics = await mcpSessions.serverMetrics(serverId: serverId)
        if metrics.isEmpty {
            let states = await mcpSessions.health(serverId: server)
            let lines = states.keys.sorted().map { "\($0): \(states[$0] ?? "unknown")" }
            return success([
                "title": "MCP health",
                "tool": "mcp_health",
                "server_id": server,
                "output": lines.joined(separator: "\n"),
                "detail": "\(states.count) servers",
                "is_mcp": "true"
            ], startDate: startDate)
        }

        var lines: [String] = []
        for m in metrics {
            var caps: [String] = []
            if m.capabilities.supportsTools { caps.append("tools") }
            if m.capabilities.supportsResources { caps.append("resources") }
            if m.capabilities.supportsPrompts { caps.append("prompts") }
            if m.capabilities.supportsLogging { caps.append("logging") }
            if m.capabilities.supportsResourceSubscriptions { caps.append("subscriptions") }

            lines.append("""
            \(m.serverId) (\(m.serverName)):
              status: \(m.status)
              uptime: \(m.uptimeSeconds)s
              calls: \(m.totalCalls) total, \(m.failedCalls) failed
              latency: avg \(m.avgLatencyMs)ms, p95 \(m.p95LatencyMs)ms
              tools: \(m.toolCount), resources: \(m.resourceCount), prompts: \(m.promptCount)
              capabilities: [\(caps.joined(separator: ", "))]\(m.lastError.map { "\n  last_error: \($0)" } ?? "")
            """)
        }

        return success([
            "title": "MCP health (detailed)",
            "tool": "mcp_health",
            "server_id": serverId ?? "",
            "output": lines.joined(separator: "\n"),
            "detail": "\(metrics.count) servers",
            "is_mcp": "true"
        ], startDate: startDate)
    }

    func executeMCPListServers(context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }
        let servers = await mcpSessions.listServers()
        let lines = servers.map { "\($0.id) (\($0.name)) [\($0.source)]" }
        return success([
            "title": "MCP servers",
            "tool": "mcp_list_servers",
            "output": lines.joined(separator: "\n"),
            "detail": "\(servers.count) servers",
            "is_mcp": "true"
        ], startDate: startDate)
    }

    func executeMCPReconnect(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }
        let serverId = resolveMCPServerArg(from: call.args)
        guard !serverId.isEmpty else {
            return failure("Missing required server", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        do {
            try await mcpSessions.reconnect(serverId: serverId)
            return success([
                "title": "MCP reconnect",
                "tool": "mcp_reconnect",
                "server_id": serverId,
                "detail": "Connection re-established",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    /// Execute a natively-registered MCP tool. The LLM calls it by function name;
    /// we route to the correct server and original tool name via the registry.

    func executeNativeMCPTool(
        functionName: String,
        route: (serverId: String, toolName: String),
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }

        let metadataKeys: Set<String> = ["id", "name", "tool", "tool_name", "function", "function_name", "is_partial", "type", "status", "title", "detail", "output"]

        do {
            let result: (serverId: String, serverName: String, content: String, isError: Bool)
            if let rich = call.richArgs, !rich.isEmpty {
                var richFiltered = rich
                for key in metadataKeys { richFiltered.removeValue(forKey: key) }
                result = try await mcpSessions.callToolRich(
                    serverId: route.serverId,
                    toolName: route.toolName,
                    arguments: richFiltered,
                    timeoutMs: context.policy.mcpPerCallTimeoutMs,
                    idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
                )
            } else {
                var args = call.args
                for key in metadataKeys { args.removeValue(forKey: key) }
                result = try await mcpSessions.callTool(
                    serverId: route.serverId,
                    toolName: route.toolName,
                    arguments: args,
                    timeoutMs: context.policy.mcpPerCallTimeoutMs,
                    idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
                )
            }

            var payload: [String: String] = [
                "title": "\(result.serverName)/\(route.toolName)",
                "tool": functionName,
                "mcp_server": result.serverName,
                "server_id": result.serverId,
                "mcp_tool": route.toolName,
                "output": truncate(result.content, maxBytes: context.policy.maxBashOutputBytes),
                "mcp_latency_ms": "\(max(1, Int(Date().timeIntervalSince(startDate) * 1000)))",
                "is_mcp": "true"
            ]
            if result.isError {
                payload["detail"] = "MCP server responded with isError=true"
            }
            return ToolResult(
                ok: !result.isError,
                payload: payload,
                durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
            )
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: [
                "mcp_tool": route.toolName,
                "server_id": route.serverId,
                "is_mcp": "true"
            ])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: [
                "mcp_tool": route.toolName,
                "server_id": route.serverId,
                "is_mcp": "true"
            ])
        }
    }

}
