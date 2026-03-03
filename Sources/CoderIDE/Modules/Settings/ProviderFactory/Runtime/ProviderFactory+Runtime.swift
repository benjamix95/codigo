import CoderEngine
import Foundation

extension ProviderFactory {
    /// Build a UnifiedToolRuntime with optional codebase index
    static func buildRuntime(
        executionController: ExecutionController?,
        executionScope: ExecutionScope,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        webSearchProvider: String? = nil,
        webSearchApiKeys: [String: String]? = nil,
        terminalBridge: (any TerminalBridge)? = nil,
        browserBridge: (any BrowserBridge)? = nil
    ) -> UnifiedToolRuntime {
        UnifiedToolRuntime(
            executionController: executionController,
            executionScope: executionScope,
            index: codebaseIndex,
            workspacePaths: workspacePaths,
            webSearchProvider: webSearchProvider,
            webSearchApiKeys: webSearchApiKeys,
            terminalBridge: terminalBridge,
            browserBridge: browserBridge
        )
    }
}
