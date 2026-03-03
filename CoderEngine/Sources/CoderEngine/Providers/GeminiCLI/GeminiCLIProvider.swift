import Foundation

/// Provider that uses Gemini CLI (`gemini -p`)
public final class GeminiCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "gemini-cli"
    public let displayName = "Gemini CLI"
    public let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: false,
        nativeDocument: false,
        nativeFile: false
    )

    let geminiPath: String
    let modelOverride: String?
    let executionController: ExecutionController?
    let executionScope: ExecutionScope
    let environmentOverride: [String: String]?

    public init(
        geminiPath: String? = nil,
        modelOverride: String? = nil,
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        if let candidate = geminiPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !candidate.isEmpty,
           FileManager.default.isExecutableFile(atPath: candidate) {
            self.geminiPath = candidate
        } else {
            self.geminiPath = GeminiDetector.findGeminiPath(customPath: nil) ?? "/opt/homebrew/bin/gemini"
        }
        self.modelOverride = modelOverride?.isEmpty == true ? nil : modelOverride
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }

    public func isAuthenticated() -> Bool {
        guard FileManager.default.fileExists(atPath: geminiPath) else { return false }
        return GeminiDetector.checkAuth(geminiPath: geminiPath)
    }

    func shellEnvironment() -> [String: String] {
        var env = GeminiDetector.shellEnvironment()
        if let override = environmentOverride {
            env.merge(override) { _, new in new }
        }
        return env
    }
}
