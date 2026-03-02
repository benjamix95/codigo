import Foundation
import os

extension UnifiedToolRuntime {
    func executeMCPLogs(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server
        let action = (call.args["action"] ?? "read").lowercased()
        let validActions: Set<String> = ["read", "set_level", "clear"]
        guard validActions.contains(action) else {
            return failure("Invalid action '\(action)'. Use read, set_level, or clear.", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }

        switch action {
        case "set_level":
            let level = (call.args["level"] ?? "info").lowercased()
            guard let sid = serverId, !sid.isEmpty else {
                return failure("'server' is required for set_level action", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
            }
            do {
                try await mcpSessions.setLogLevel(serverId: sid, level: level)
                return success([
                    "title": "MCP log level set",
                    "tool": "mcp_logs",
                    "server_id": sid,
                    "detail": "Stored locally as \(level) (server passthrough unavailable in current SDK).",
                    "is_mcp": "true"
                ], startDate: startDate)
            } catch let err as ToolRuntimeError {
                return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
            } catch {
                return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
            }
        case "clear":
            await mcpSessions.logStore.clear(serverId: serverId)
            return success([
                "title": "MCP logs cleared",
                "tool": "mcp_logs",
                "server_id": serverId ?? "",
                "detail": "Log buffer cleared",
                "is_mcp": "true"
            ], startDate: startDate)
        default:
            let severity = call.args["severity"] ?? "info"
            let limit = Int(call.args["limit"] ?? "50") ?? 50
            let entries = await mcpSessions.logStore.logs(serverId: serverId, severity: severity, limit: limit)
            if entries.isEmpty {
                return success([
                    "title": "MCP logs",
                    "tool": "mcp_logs",
                    "server_id": serverId ?? "",
                    "output": "(no log entries)",
                    "detail": "0 entries",
                    "is_mcp": "true"
                ], startDate: startDate)
            }
            let df = ISO8601DateFormatter()
            let lines = entries.map { e in
                let ts = df.string(from: e.timestamp)
                let logger = e.logger.map { " [\($0)]" } ?? ""
                return "\(ts) [\(e.level.uppercased())]\(logger) \(e.serverId): \(e.message)"
            }
            return success([
                "title": "MCP logs",
                "tool": "mcp_logs",
                "server_id": serverId ?? "",
                "output": truncate(lines.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
                "detail": "\(entries.count) entries",
                "is_mcp": "true"
            ], startDate: startDate)
        }
    }

    func executeMCPRestartServer(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let serverId = resolveMCPServerArg(from: call.args)
        guard !serverId.isEmpty else {
            return failure("Missing required 'server' argument", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        do {
            try await mcpSessions.restartServer(serverId: serverId)
            return success([
                "title": "MCP restart",
                "tool": "mcp_restart_server",
                "server_id": serverId,
                "detail": "Server fully restarted and reconnected",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }
}
