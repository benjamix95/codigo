import Foundation

/// Provider che usa Claude Code CLI (`claude -p`)
public final class ClaudeCLIProvider: LLMProvider, @unchecked Sendable {
    public static let defaultAllowedTools = ["Read", "Edit", "Bash", "Write", "Search", "Task"]

    public let id = "claude-cli"
    public let displayName = "Claude Code CLI"
    public let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: true,
        nativeDocument: false,
        nativeFile: false
    )
    
    private let claudePath: String
    private let model: String?
    private let allowedTools: [String]
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope
    private let environmentOverride: [String: String]?

    public init(
        claudePath: String? = nil,
        model: String? = nil,
        allowedTools: [String] = ClaudeCLIProvider.defaultAllowedTools,
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        if let candidate = claudePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !candidate.isEmpty,
           FileManager.default.isExecutableFile(atPath: candidate) {
            self.claudePath = candidate
        } else {
            self.claudePath = PathFinder.find(executable: "claude") ?? "/usr/local/bin/claude"
        }
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = (normalizedModel?.isEmpty == false) ? normalizedModel : nil
        self.allowedTools = Self.normalizeTools(allowedTools)
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }
    
    public func isAuthenticated() -> Bool {
        let status = ClaudeDetector.detect(customPath: claudePath)
        return status.isInstalled && status.isLoggedIn
    }
    
    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let systemBlock = context.systemPromptOverride ?? context.resolvedStandardAgentSystemPrompt
        let fullPrompt = Self.buildPrompt(
            systemBlock: systemBlock,
            prompt: prompt,
            contextPrompt: context.contextPrompt(),
            imageURLs: imageURLs
        )
        
        let path = claudePath
        let workspacePath = context.workspacePath
        let model = self.model
        let allowedTools = self.allowedTools
        let environmentOverride = self.environmentOverride
        let executionController = self.executionController
        let executionScope = self.executionScope
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await runStreamingRequest(
                        path: path,
                        workspacePath: workspacePath,
                        fullPrompt: fullPrompt,
                        model: model,
                        allowedTools: allowedTools,
                        environmentOverride: environmentOverride,
                        executionController: executionController,
                        executionScope: executionScope,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    static func buildPrompt(
        systemBlock: String,
        prompt: String,
        contextPrompt: String,
        imageURLs: [URL]?
    ) -> String {
        let basePrompt = systemBlock + "\n\n" + prompt + contextPrompt
        if let urls = imageURLs, !urls.isEmpty {
            let refs = urls.map { "[Image: \($0.path)]" }.joined(separator: "\n")
            return refs + "\n\n" + basePrompt
        }
        return basePrompt
    }
    
    static func buildCLIArguments(
        fullPrompt: String,
        model: String?,
        allowedTools: [String]
    ) -> [String] {
        var args = [
            "-p", fullPrompt,
            "--output-format", "stream-json",
            "--verbose",
        ]
        if let model {
            args += ["--model", model]
        }
        if !allowedTools.isEmpty {
            args += ["--allowedTools", allowedTools.joined(separator: ",")]
        }
        return args
    }

    static func normalizeTools(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        if result.isEmpty {
            return defaultAllowedTools
        }
        return result
    }

    static func mergedEnvironment(with override: [String: String]?) -> [String: String] {
        var env = ClaudeDetector.shellEnvironment()
        if let override {
            env.merge(override) { _, new in new }
        }
        return env
    }
}
