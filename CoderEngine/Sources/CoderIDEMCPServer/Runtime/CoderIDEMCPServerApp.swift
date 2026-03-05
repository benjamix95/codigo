import Foundation
import CoderEngine
import MCP

@main
struct CoderIDEMCPServerApp {
    static func main() async throws {
        // Parse arguments: --workspace <path>
        let args = CommandLine.arguments
        let workspacePath: String
        if let idx = args.firstIndex(of: "--workspace"), idx + 1 < args.count {
            workspacePath = args[idx + 1]
        } else {
            workspacePath = FileManager.default.currentDirectoryPath
        }

        let workspaceURL = URL(fileURLWithPath: workspacePath)

        // Build the runtime with a live codebase index so codebase_search/find_symbol/find_files work.
        let codebaseIndex = CodebaseIndex()
        let runtime = UnifiedToolRuntime(
            executionController: nil,
            executionScope: .agent,
            mcpSessions: MCPSessionManager(),
            index: codebaseIndex,
            workspacePaths: [workspaceURL],
            excludedPaths: [],
            webSearchProvider: nil,
            webSearchApiKeys: nil
        )

        let context = ToolExecutionContext(
            workspaceContext: WorkspaceContext(
                workspacePath: workspaceURL,
                excludedPaths: []
            ),
            policy: ToolRuntimePolicy(
                sandboxMode: "workspace-write",
                askForApproval: "never",
                timeoutMs: 120_000,
                maxBashOutputBytes: 256_000,
                maxReadBytesPerFile: 512_000,
                enableMCP: false  // Don't recurse into MCP from this server
            ),
            executionScope: .agent
        )

        // Create MCP server
        let server = Server(
            name: "coderide-tools",
            version: "1.0.0",
            instructions: """
                CoderIDE Tool Server — provides file operations, search, editing, \
                web search, and diagnostics tools for the current workspace. \
                Prefer these tools over shell commands for file operations and code search.
                """,
            capabilities: .init(
                tools: .init(listChanged: false)
            )
        )

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: CoderIDETools.all)
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            let toolName = CoderIDETools.runtimeToolName(from: params.name)
            let isEditRuntimeTool = Self.mcpEditRuntimeTools.contains(toolName)

            // Convert MCP Value args → [String: String] for UnifiedToolRuntime
            var stringArgs: [String: String] = [:]
            var richArgs: [String: any Sendable] = [:]
            if let arguments = params.arguments {
                for (key, value) in arguments {
                    stringArgs[key] = valueToString(value)
                    richArgs[key] = valueToSendable(value)
                }
            }

            // IDE state tools are pass-through: accepted by MCP server,
            // actual state management happens on the UI side via stream event pipeline.
            if toolName == "debug_panel" {
                return CallTool.Result(
                    content: [.text("tool_validation_error: legacy tool 'debug_panel' is not supported. Use debug_set_phase/debug_request_user/debug_resolve.")],
                    isError: true
                )
            }
            if Self.ideStateTools.contains(toolName) {
                return handleIDEStateTool(name: toolName, args: stringArgs)
            }

            let call = ToolCall(
                id: UUID().uuidString,
                name: toolName,
                args: stringArgs,
                sourceProvider: "coderide-mcp",
                swarmId: nil,
                scope: .agent,
                richArgs: richArgs.isEmpty ? nil : richArgs
            )

            let events = await runtime.execute(call, context: context)

            // Extract result from stream events
            var output = ""
            var isError = false
            var bestPayload: [String: String] = [:]
            var bestPayloadScore = Int.min
            for event in events {
                if case .raw(let type, let payload) = event {
                    let score = Self.payloadScore(payload: payload)
                    if score >= bestPayloadScore {
                        bestPayload = payload
                        bestPayloadScore = score
                    }
                    if let payloadOutput = payload["output"], !payloadOutput.isEmpty {
                        output = payloadOutput
                    }
                    if let detail = payload["detail"], output.isEmpty {
                        output = detail
                    }
                    if let stderr = payload["stderr"], !stderr.isEmpty {
                        if !output.isEmpty { output += "\n" }
                        output += stderr
                    }
                    if payload["status"] == "failed" || type.contains("error") {
                        isError = true
                    }
                }
            }

            if isEditRuntimeTool {
                let structuredPayload = Self.structuredMCPEditPayload(
                    toolName: toolName,
                    toolCallID: call.id,
                    payload: bestPayload,
                    isError: isError
                )
                if let json = Self.encodeJSONObjectString(structuredPayload) {
                    return CallTool.Result(
                        content: [.text(json)],
                        isError: isError ? true : nil
                    )
                }
            }

            if output.isEmpty {
                output = isError ? "Tool execution failed" : "OK"
            }

            return CallTool.Result(
                content: [.text(output)],
                isError: isError ? true : nil
            )
        }

        // Start stdio transport
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
