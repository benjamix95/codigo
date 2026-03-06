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
        let languageRuntimeBridge: (any RuntimeLanguageService)? = codebaseIndex.map {
            LanguageServiceRuntimeBridge(service: LanguageService(codebaseIndex: $0))
        }
        return UnifiedToolRuntime(
            executionController: executionController,
            executionScope: executionScope,
            mcpSessions: MCPRuntimeService.sharedSessionManager,
            index: codebaseIndex,
            workspacePaths: workspacePaths,
            webSearchProvider: webSearchProvider,
            webSearchApiKeys: webSearchApiKeys,
            terminalBridge: terminalBridge,
            browserBridge: browserBridge,
            languageService: languageRuntimeBridge
        )
    }
}
