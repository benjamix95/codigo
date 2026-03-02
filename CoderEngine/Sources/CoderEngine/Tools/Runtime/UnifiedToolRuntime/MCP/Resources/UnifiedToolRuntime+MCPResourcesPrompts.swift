import Foundation
import os

extension UnifiedToolRuntime {
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

}
