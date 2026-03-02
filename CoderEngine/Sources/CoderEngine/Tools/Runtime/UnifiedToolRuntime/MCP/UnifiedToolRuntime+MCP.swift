import Foundation
import os

extension UnifiedToolRuntime {
    func canFallbackToMCP(toolName: String, call: ToolCall) -> Bool {
        if toolName == "mcp" || toolName == "mcp_call" || toolName.hasPrefix("mcp_") {
            return true
        }
        if isQualifiedMCPToolReference(toolName) {
            return true
        }
        if toolName.hasPrefix("coderide_") {
            return true
        }
        let hasToolArg = call.args["tool"] != nil || call.args["mcp_tool"] != nil
        let hasServerArg = call.args["server"] != nil || call.args["server_id"] != nil || call.args["mcp_server"] != nil
        return hasToolArg && (hasServerArg || toolName == "mcp" || toolName == "mcp_call")
    }

    func resolveMCPServerArg(from args: [String: String]) -> String {
        (args["server"] ?? args["server_id"] ?? args["mcp_server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isQualifiedMCPToolReference(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return false }
        return isValidMCPIdentifier(parts[0]) && isValidMCPIdentifier(parts[1])
    }

    func isValidMCPIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[A-Za-z0-9_.:-]{1,128}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    struct MCPInvocation {
        let serverId: String?
        let toolName: String
        let arguments: [String: String]
    }

    private static let mcpWrapperKeys: Set<String> = [
        "name", "id", "tool", "mcp_tool", "server", "server_id", "mcp_server", "args"
    ]

    func buildMCPInvocation(
        call: ToolCall,
        fallbackToolName: String? = nil
    ) throws -> MCPInvocation {
        let toolFromArgs = (call.args["tool"] ?? call.args["mcp_tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTool = (fallbackToolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedToolRaw = !toolFromArgs.isEmpty ? toolFromArgs : fallbackTool
        guard !requestedToolRaw.isEmpty else {
            throw ToolRuntimeError.validation("Missing MCP tool name")
        }

        let server = (call.args["server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serverID = (call.args["server_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let mcpServer = (call.args["mcp_server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serverCandidates = [server, serverID, mcpServer].filter { !$0.isEmpty }
        if Set(serverCandidates).count > 1 {
            throw ToolRuntimeError.validation("Conflicting MCP server values in server/server_id/mcp_server")
        }
        let explicitServer = serverCandidates.first

        let parsedServer: String?
        let parsedTool: String
        if requestedToolRaw.contains("/") {
            let parts = requestedToolRaw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else {
                throw ToolRuntimeError.validation("Ambiguous MCP tool reference '\(requestedToolRaw)'")
            }
            guard isValidMCPIdentifier(parts[0]), isValidMCPIdentifier(parts[1]) else {
                throw ToolRuntimeError.validation("Invalid MCP server/tool identifier in '\(requestedToolRaw)'")
            }
            if let explicitServer, explicitServer != parts[0] {
                throw ToolRuntimeError.validation("Conflicting MCP server between tool reference and server argument")
            }
            parsedServer = parts[0]
            parsedTool = parts[1]
        } else {
            guard isValidMCPIdentifier(requestedToolRaw) else {
                throw ToolRuntimeError.validation("Invalid MCP tool identifier '\(requestedToolRaw)'")
            }
            if let explicitServer, !explicitServer.isEmpty, !isValidMCPIdentifier(explicitServer) {
                throw ToolRuntimeError.validation("Invalid MCP server identifier '\(explicitServer)'")
            }
            parsedServer = explicitServer
            parsedTool = requestedToolRaw
        }

        var mergedArgs: [String: String] = [:]
        let embeddedArgs = parseEmbeddedArgs(call.args["args"])
        for (key, value) in embeddedArgs {
            mergedArgs[key] = value
        }
        for (key, value) in call.args where !Self.mcpWrapperKeys.contains(key) {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidMCPIdentifier(trimmedKey) else {
                throw ToolRuntimeError.validation("Unsupported MCP argument key '\(key)'")
            }
            mergedArgs[trimmedKey] = value
        }

        return MCPInvocation(serverId: parsedServer, toolName: parsedTool, arguments: mergedArgs)
    }

    public func executeMCP(call: ToolCall, context: ToolExecutionContext) async -> ToolResult {
        await executeMCPCall(call: call, context: context, startDate: Date())
    }

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

    func executeMCPListResources(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server
        do {
            let resources = try await mcpSessions.listResources(serverId: serverId, idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds)
            let templates = try await mcpSessions.listResourceTemplates(serverId: serverId, idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds)

            var lines: [String] = []
            for r in resources {
                let mime = r.mimeType.map { " (\($0))" } ?? ""
                let desc = r.description.map { " — \($0)" } ?? ""
                lines.append("\(r.serverId)/\(r.uri): \(r.name)\(mime)\(desc)")
            }
            if !templates.isEmpty {
                lines.append("\n--- Resource Templates ---")
                for t in templates {
                    let desc = t.description.map { " — \($0)" } ?? ""
                    lines.append("\(t.serverId)/\(t.uriTemplate): \(t.name)\(desc)")
                }
            }

            return success([
                "title": "MCP resources",
                "tool": "mcp_list_resources",
                "server_id": serverId ?? "",
                "output": truncate(lines.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
                "detail": "\(resources.count) resources, \(templates.count) templates",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    func executeMCPReadResource(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let uri = (call.args["uri"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty else {
            return failure("Missing required 'uri' argument", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server

        do {
            let content = try await mcpSessions.readResource(serverId: serverId, uri: uri, idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds)
            let output: String
            if let text = content.text {
                output = text
            } else if let blob = content.blob {
                output = "[binary \(content.mimeType ?? "application/octet-stream")] \(blob.count) bytes (base64)"
            } else {
                output = "(empty resource)"
            }
            return success([
                "title": "MCP resource \(uri)",
                "tool": "mcp_read_resource",
                "server_id": content.serverId,
                "mcp_server": content.serverName,
                "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                "detail": content.mimeType ?? "unknown type",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    func executeMCPSubscribe(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let uri = (call.args["uri"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let server = resolveMCPServerArg(from: call.args)
        let action = (call.args["action"] ?? "subscribe").lowercased()
        let validActions: Set<String> = ["subscribe", "unsubscribe"]

        guard !uri.isEmpty else {
            return failure("Missing required 'uri' argument", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        guard !server.isEmpty else {
            return failure("Missing required 'server' argument", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        guard validActions.contains(action) else {
            return failure("Invalid action '\(action)'. Use subscribe or unsubscribe.", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }

        do {
            if action == "unsubscribe" {
                await mcpSessions.unsubscribeResource(serverId: server, uri: uri)
                return success([
                    "title": "MCP unsubscribe",
                    "tool": "mcp_subscribe",
                    "server_id": server,
                    "detail": "Unsubscribed from \(uri)",
                    "is_mcp": "true"
                ], startDate: startDate)
            } else {
                try await mcpSessions.subscribeResource(serverId: server, uri: uri)
                return success([
                    "title": "MCP subscribe",
                    "tool": "mcp_subscribe",
                    "server_id": server,
                    "detail": "Subscribed to \(uri)",
                    "is_mcp": "true"
                ], startDate: startDate)
            }
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    func executeMCPListPrompts(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server

        do {
            let prompts = try await mcpSessions.listPrompts(serverId: serverId, idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds)
            let lines = prompts.map { p -> String in
                let args = p.arguments.isEmpty ? "" : " args: \(p.arguments.map { "\($0.name)\($0.required ? "*" : "")" }.joined(separator: ", "))"
                let desc = p.description.map { " — \($0)" } ?? ""
                return "\(p.serverId)/\(p.name)\(desc)\(args)"
            }
            return success([
                "title": "MCP prompts",
                "tool": "mcp_list_prompts",
                "server_id": serverId ?? "",
                "output": truncate(lines.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
                "detail": "\(prompts.count) prompts discovered",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

    func executeMCPGetPrompt(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        if !context.policy.enableMCP {
            return failure("MCP disabled by policy", errorCode: ToolRuntimeError.mcpUnavailable("disabled").errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        }
        let promptName = (call.args["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptName.isEmpty else {
            return failure("Missing required 'name' argument", errorCode: "validation", startDate: startDate, payload: ["is_mcp": "true"])
        }
        let server = resolveMCPServerArg(from: call.args)
        let serverId = server.isEmpty ? nil : server

        var promptArgsRich: [String: Any] = [:]
        if let richArgs = call.richArgs, !richArgs.isEmpty {
            if let explicitArgs = richArgs["args"] as? [String: Any] {
                for (key, value) in explicitArgs {
                    promptArgsRich[key] = value
                }
            } else if let explicitArgs = richArgs["args"] as? [String: any Sendable] {
                for (key, value) in explicitArgs {
                    promptArgsRich[key] = value
                }
            }
            for (key, value) in richArgs where !Self.mcpWrapperKeys.contains(key) {
                promptArgsRich[key] = value
            }
        }

        if let argsJSON = call.args["args"], !argsJSON.isEmpty,
           let data = argsJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in parsed {
                if promptArgsRich[key] == nil {
                    promptArgsRich[key] = value
                }
            }
        }

        for (key, rawValue) in call.args where !Self.mcpWrapperKeys.contains(key) {
            if promptArgsRich[key] != nil {
                continue
            }
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                promptArgsRich[key] = ""
                continue
            }
            if trimmed == "true" {
                promptArgsRich[key] = true
                continue
            }
            if trimmed == "false" {
                promptArgsRich[key] = false
                continue
            }
            if let intValue = Int(trimmed) {
                promptArgsRich[key] = intValue
                continue
            }
            if let doubleValue = Double(trimmed), trimmed.contains(".") {
                promptArgsRich[key] = doubleValue
                continue
            }
            if let data = trimmed.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                promptArgsRich[key] = parsed
                continue
            }
            promptArgsRich[key] = trimmed
        }

        do {
            let result: MCPPromptResult
            if promptArgsRich.isEmpty {
                result = try await mcpSessions.getPrompt(
                    serverId: serverId,
                    name: promptName,
                    arguments: [:],
                    idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
                )
            } else {
                result = try await mcpSessions.getPromptRich(
                    serverId: serverId,
                    name: promptName,
                    arguments: promptArgsRich,
                    idleTTLSeconds: context.policy.mcpSessionIdleTTLSeconds
                )
            }
            var output = ""
            if let desc = result.description {
                output += "Description: \(desc)\n\n"
            }
            for msg in result.messages {
                output += "[\(msg.role)]\n\(msg.content)\n\n"
            }
            return success([
                "title": "MCP prompt \(promptName)",
                "tool": "mcp_get_prompt",
                "server_id": result.serverId,
                "mcp_server": result.serverName,
                "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                "detail": "\(result.messages.count) messages",
                "is_mcp": "true"
            ], startDate: startDate)
        } catch let err as ToolRuntimeError {
            return failure(err.localizedDescription, errorCode: err.errorCode, startDate: startDate, payload: ["is_mcp": "true"])
        } catch {
            return failure(error.localizedDescription, errorCode: "transport", startDate: startDate, payload: ["is_mcp": "true"])
        }
    }

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
