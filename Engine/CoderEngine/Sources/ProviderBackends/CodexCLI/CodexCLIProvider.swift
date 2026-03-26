import Foundation

/// Codex sandbox mode: read-only, workspace-write, danger-full-access
public enum CodexSandboxMode: String, CaseIterable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

/// Markers the model can emit to activate the Task Activity Panel
public enum CoderIDEMarkers {
    public static let showTaskPanel = "[CODERIDE:show_task_panel]"
    public static let showSwarmPanel = "[CODERIDE:show_swarm_panel]"
    @available(*, deprecated, message: "invoke_swarm replaced by inline subagent_* tools")
    public static let invokeSwarmPrefix = "[CODERIDE:invoke_swarm:"
    @available(*, deprecated, message: "invoke_swarm replaced by inline subagent_* tools")
    public static let invokeSwarmSuffix = "]"
    public static let todoWritePrefix = "[CODERIDE:todo_write|"
    public static let todoRead = "[CODERIDE:todo_read]"
    public static let instantGrepPrefix = "[CODERIDE:instant_grep|"
    public static let planStepPrefix = "[CODERIDE:plan_step|"
    public static let readBatchPrefix = "[CODERIDE:read_batch|"
    public static let webSearchPrefix = "[CODERIDE:web_search|"
}

/// Provider that uses Codex CLI (`codex exec`)
public final class CodexCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "codex-cli"
    public let displayName = "Codex CLI"
    public let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: true,
        nativeDocument: false,
        nativeFile: false
    )
    
    private let codexPath: String
    private let sandboxMode: CodexSandboxMode
    private let modelOverride: String?
    private let modelReasoningEffort: String?
    private let modelProviderOverride: String?
    private let fastMode: Bool
    private let preferOpenAIResponsesWireAPI: Bool
    private let yoloMode: Bool
    private let askForApproval: String
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope
    private let environmentOverride: [String: String]?

    public init(
        codexPath: String? = nil,
        sandboxMode: CodexSandboxMode = .workspaceWrite,
        modelOverride: String? = nil,
        modelReasoningEffort: String? = nil,
        modelProviderOverride: String? = nil,
        fastMode: Bool = true,
        preferOpenAIResponsesWireAPI: Bool = false,
        yoloMode: Bool = false,
        askForApproval: String? = nil,
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        if let candidate = codexPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !candidate.isEmpty,
           FileManager.default.isExecutableFile(atPath: candidate) {
            self.codexPath = candidate
        } else {
            self.codexPath = PathFinder.find(executable: "codex") ?? "/usr/local/bin/codex"
        }
        self.sandboxMode = sandboxMode
        self.modelOverride = modelOverride?.isEmpty == true ? nil : modelOverride
        self.modelReasoningEffort = modelReasoningEffort?.isEmpty == true ? nil : modelReasoningEffort
        self.modelProviderOverride = modelProviderOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? modelProviderOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        self.fastMode = fastMode
        self.preferOpenAIResponsesWireAPI = preferOpenAIResponsesWireAPI
        self.yoloMode = yoloMode
        self.askForApproval = Self.normalizeAskForApproval(askForApproval)
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }

    public static func normalizeAskForApproval(_ raw: String?) -> String {
        let allowed = Set(["never", "on-request", "untrusted"])
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "never"
        }

        while value.hasPrefix("-") {
            value.removeFirst()
        }

        if value == "ask-for-approval" {
            return "never"
        }
        return allowed.contains(value) ? value : "never"
    }
    
    public func isAuthenticated() -> Bool {
        if CodexDetector.hasAuthFile() { return true }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["login", "status"]
        process.standardOutput = nil
        process.standardError = nil
        var env = CodexDetector.shellEnvironment()
        if let override = environmentOverride {
            env.merge(override) { _, new in new }
        }
        process.environment = env
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let systemBlock = context.systemPromptOverride ?? context.resolvedStandardAgentSystemPrompt
        let fullPrompt = systemBlock + "\n\n" + prompt + context.contextPrompt()
        let path = codexPath
        let workspacePath = context.workspacePath
        
        return AsyncThrowingStream { continuation in
            let producerTask = Task {
                var parserState = CodexStreamParserState(workspacePath: workspacePath.path)
                do {
                    let execPath = path
                    guard FileManager.default.fileExists(atPath: execPath) else {
                        continuation.yield(.error("Codex CLI not found at \(execPath). Install with: brew install codex"))
                        continuation.finish(throwing: CoderEngineError.cliNotFound("codex"))
                        return
                    }
                    
                    let args = Self.buildExecArguments(
                        fullPrompt: fullPrompt,
                        imageURLs: imageURLs,
                        sandboxMode: sandboxMode,
                        yoloMode: yoloMode,
                        askForApproval: askForApproval,
                        workspacePath: workspacePath.path,
                        modelOverride: modelOverride,
                        modelReasoningEffort: modelReasoningEffort,
                        modelProviderOverride: modelProviderOverride,
                        fastMode: fastMode,
                        preferOpenAIResponsesWireAPI: preferOpenAIResponsesWireAPI
                    )
                    
                    var env = CodexDetector.shellEnvironment()
                    if let override = environmentOverride {
                        env.merge(override) { _, new in new }
                    }
                    Self.repairCodexConfigIfNeeded(environment: env)
                    let invocation = Self.streamInvocation(
                        executable: execPath,
                        arguments: args
                    )
                    let stream = try await ProcessRunner.run(
                        executable: invocation.executable,
                        arguments: invocation.arguments,
                        workingDirectory: workspacePath,
                        environment: env,
                        executionController: executionController,
                        scope: executionScope
                    )
                    
                    continuation.yield(.started)
                    for try await rawLine in stream {
                        try Task.checkCancellation()
                        let payloads = Self.parseStreamJSONPayloads(from: rawLine, state: &parserState)
                        guard !payloads.isEmpty else { continue }
                        for json in payloads {
                            for event in Self.parseStreamJSONEvent(json, state: &parserState) {
                                continuation.yield(event)
                            }
                        }
                    }
                    for event in Self.finalizeStreamJSONState(state: &parserState) {
                        continuation.yield(event)
                    }
                    continuation.yield(.completed)
                    continuation.finish()
                } catch is CancellationError {
                    for event in Self.finalizeStreamJSONState(state: &parserState) {
                        continuation.yield(event)
                    }
                    continuation.finish(throwing: CancellationError())
                } catch {
                    for event in Self.finalizeStreamJSONState(state: &parserState) {
                        continuation.yield(event)
                    }
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                producerTask.cancel()
            }
        }
    }


}
