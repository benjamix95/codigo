import Foundation

/// Provider that uses Kilo CLI (`kilo run --format json`)
public final class KiloCLIProvider: LLMProvider, @unchecked Sendable {
    public let id = "kilo-cli"
    public let displayName = "Kilo CLI"
    public let attachmentCapabilities = ProviderAttachmentCapabilities(
        nativeImage: false,
        nativeDocument: false,
        nativeFile: false
    )

    private let kiloPath: String
    private let model: String?
    private let executionController: ExecutionController?
    private let executionScope: ExecutionScope
    private let environmentOverride: [String: String]?

    public init(
        kiloPath: String? = nil,
        model: String? = nil,
        executionController: ExecutionController? = nil,
        executionScope: ExecutionScope = .agent,
        environmentOverride: [String: String]? = nil
    ) {
        if let candidate = kiloPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !candidate.isEmpty,
           FileManager.default.isExecutableFile(atPath: candidate) {
            self.kiloPath = candidate
        } else {
            self.kiloPath = PathFinder.find(executable: "kilo") ?? "/opt/homebrew/bin/kilo"
        }
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = (normalizedModel?.isEmpty == false) ? normalizedModel : nil
        self.executionController = executionController
        self.executionScope = executionScope
        self.environmentOverride = environmentOverride
    }

    public func isAuthenticated() -> Bool {
        KiloDetector.detect(customPath: kiloPath).isInstalled
    }

    public func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]? = nil
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let systemBlock = context.systemPromptOverride ?? SystemPrompts.taskCompletionStrict
        let fullPrompt = systemBlock + "\n\n" + prompt + context.contextPrompt()
        let path = kiloPath
        let workspacePath = context.workspacePath
        let model = self.model
        let environmentOverride = self.environmentOverride
        let executionController = self.executionController
        let executionScope = self.executionScope

        return AsyncThrowingStream { continuation in
            let producerTask = Task {
                do {
                    try await KiloCLIExecution.runStreamingRequest(
                        path: path,
                        workspacePath: workspacePath,
                        fullPrompt: fullPrompt,
                        model: model,
                        imageURLs: imageURLs,
                        environmentOverride: environmentOverride,
                        executionController: executionController,
                        executionScope: executionScope,
                        continuation: continuation
                    )
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                producerTask.cancel()
            }
        }
    }

    static func mergedEnvironment(with override: [String: String]?) -> [String: String] {
        var env = CodexDetector.shellEnvironment()
        if let override {
            env.merge(override) { _, new in new }
        }
        return env
    }
}
