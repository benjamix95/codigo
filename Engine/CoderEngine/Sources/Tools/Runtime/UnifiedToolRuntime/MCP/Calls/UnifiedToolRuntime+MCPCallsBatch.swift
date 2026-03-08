import Foundation
import os

extension UnifiedToolRuntime {
    func executeMCPDirectToolFallback(
        toolName: String,
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        do {
            let invocation = try buildMCPInvocation(call: call, fallbackToolName: toolName)
            let result = try await mcpSessions.callTool(
                serverId: invocation.serverId,
                toolName: invocation.toolName,
                arguments: invocation.arguments,
                timeoutMs: context.policy.mcpPerCallTimeoutMs,
                idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
            )
            return success([
                "title": "MCP fallback \(result.serverName)/\(invocation.toolName)",
                "tool": invocation.toolName,
                "server_id": result.serverId,
                "mcp_server": result.serverName,
                "mcp_tool": invocation.toolName,
                "output": truncate(result.content, maxBytes: context.policy.maxBashOutputBytes),
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    // MARK: - MCP Advanced Tool Executors

    func executeMCPBatch(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let callsJSON = call.args["calls"] ?? ""
        guard !callsJSON.isEmpty,
              let data = callsJSON.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return failure("Invalid 'calls' argument — expected JSON array of {server, tool, args}", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }

        let timeoutMs = Int(call.args["timeout_ms"] ?? "") ?? context.policy.mcpPerCallTimeoutMs
        var batchCalls: [(serverId: String?, toolName: String, arguments: [String: Any])] = []
        for item in parsed {
            let server = item["server"] as? String
            guard let tool = item["tool"] as? String, !tool.isEmpty else { continue }
            let args = (item["args"] as? [String: Any]) ?? [:]
            batchCalls.append((serverId: server, toolName: tool, arguments: args))
        }

        guard !batchCalls.isEmpty else {
            return failure("No valid calls in batch", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }

        let results = await mcpSessions.callToolsBatch(
            calls: batchCalls,
            timeoutMs: timeoutMs,
            idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
        )

        var outputLines: [String] = []
        var allOk = true
        for r in results {
            let status = r.isError ? "ERROR" : "OK"
            if r.isError { allOk = false }
            let tool = batchCalls[r.index].toolName
            let contentPreview = truncate(r.content, maxBytes: context.policy.maxBashOutputBytes / max(1, results.count))
            outputLines.append("[\(r.index)] \(tool) [\(status)]: \(contentPreview)")
        }

        return ToolResult(
            ok: allOk,
            payload: [
                "title": "MCP batch (\(results.count) calls)",
                "tool": "mcp_batch",
                "output": outputLines.joined(separator: "\n\n"),
                "detail": "\(results.count) calls, \(results.filter { !$0.isError }.count) succeeded",
                "is_mcp": "true"
            ],
            durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
        )
    }

}
