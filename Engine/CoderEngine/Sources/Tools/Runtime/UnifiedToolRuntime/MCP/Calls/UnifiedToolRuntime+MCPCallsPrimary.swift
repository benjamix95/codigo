import Foundation
import os

extension UnifiedToolRuntime {
    func executeMCPCall(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }
        let invocation: MCPInvocation
        do {
            invocation = try buildMCPInvocation(call: call)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }

        do {
            let result: (serverId: String, serverName: String, content: String, isError: Bool)
            if let rich = call.richArgs, !rich.isEmpty {
                var richFiltered = rich
                for key in Self.mcpWrapperKeys { richFiltered.removeValue(forKey: key) }
                result = try await mcpSessions.callToolRich(
                    serverId: invocation.serverId,
                    toolName: invocation.toolName,
                    arguments: richFiltered,
                    timeoutMs: context.policy.mcpPerCallTimeoutMs,
                    idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
                )
            } else {
                result = try await mcpSessions.callTool(
                    serverId: invocation.serverId,
                    toolName: invocation.toolName,
                    arguments: invocation.arguments,
                    timeoutMs: context.policy.mcpPerCallTimeoutMs,
                    idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
                )
            }

            var payload: [String: String] = [
                "title": "MCP \(result.serverName)/\(invocation.toolName)",
                "tool": "mcp",
                "mcp_server": result.serverName,
                "server_id": result.serverId,
                "mcp_tool": invocation.toolName,
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
                "mcp_tool": invocation.toolName,
                "server_id": invocation.serverId ?? "",
                "is_mcp": "true"
            ])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: [
                "mcp_tool": invocation.toolName,
                "server_id": invocation.serverId ?? "",
                "is_mcp": "true"
            ])
        }
    }

    func executeMCPListTools(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }

        do {
            let server = resolveMCPServerArg(from: call.args)
            let serverId = server.isEmpty ? nil : server
            let tools = try await mcpSessions.listTools(
                serverId: serverId,
                idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
            )
            let lines = tools.map { "\($0.serverId)/\($0.name): \($0.description)" }
            return success([
                "title": "MCP tool discovery",
                "tool": "mcp_list_tools",
                "server_id": serverId ?? "",
                "output": truncate(lines.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
                "detail": "\(tools.count) tools discovered",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    func executeMCPDescribeTool(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure(
                "MCP disabled by policy",
                errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }
        let toolName = (call.args["tool"] ?? call.args["mcp_tool"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolName.isEmpty else {
            return failure(
                "Missing tool name",
                errorCode: ToolRuntimeError.validation("tool missing").errorCode,
                startDate: startDate,
                payload: ["is_mcp": "true"]
            )
        }

        do {
            let serverArg = resolveMCPServerArg(from: call.args)
            let serverId = serverArg.isEmpty ? nil : serverArg
            let desc = try await mcpSessions.describeTool(serverId: serverId, toolName: toolName)
            guard let desc else {
                return failure(
                    "MCP tool not found",
                    errorCode: ToolRuntimeError.mcpUnavailable("MCP tool not found").errorCode,
                    startDate: startDate,
                    payload: ["is_mcp": "true"]
                )
            }
            return success([
                "title": "MCP describe \(desc.name)",
                "tool": "mcp_describe_tool",
                "server_id": desc.serverId,
                "mcp_tool": desc.name,
                "detail": desc.description,
                "output": truncate(desc.schema, maxBytes: context.policy.maxBashOutputBytes),
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

}
