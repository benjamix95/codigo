import CoderEngine
import Foundation

enum CodeReviewCommandRuntimeHooks {
    typealias ProviderFactoryOverride = @MainActor (
        ProviderFactoryConfig,
        ExecutionController?,
        String?,
        CodebaseIndex?,
        [URL],
        CodeReviewSessionState?,
        SessionConfig?
    ) -> (any LLMProvider)?
    typealias WorkspaceContextOverride = @MainActor (CodigoApp) -> WorkspaceContext?

    static var providerFactoryOverride: ProviderFactoryOverride?
    static var workspaceContextOverride: WorkspaceContextOverride?

    @MainActor
    static func makeProvider(
        config: ProviderFactoryConfig,
        executionController: ExecutionController?,
        agentProviderId: String?,
        codebaseIndex: CodebaseIndex?,
        workspacePaths: [URL],
        sessionState: CodeReviewSessionState? = nil,
        initialSessionConfig: SessionConfig? = nil
    ) -> (any LLMProvider)? {
        if let providerFactoryOverride {
            return providerFactoryOverride(
                config,
                executionController,
                agentProviderId,
                codebaseIndex,
                workspacePaths,
                sessionState,
                initialSessionConfig
            )
        }

        return ProviderFactory.codeReviewMultiSwarmProvider(
            config: config,
            executionController: executionController,
            agentProviderId: agentProviderId,
            codebaseIndex: codebaseIndex,
            workspacePaths: workspacePaths,
            sessionState: sessionState,
            initialSessionConfig: initialSessionConfig
        )
    }

    @MainActor
    static func workspaceContext(for app: CodigoApp) -> WorkspaceContext {
        if let workspaceContextOverride,
           let override = workspaceContextOverride(app) {
            return override
        }

        return WorkspaceContext(
            workspacePaths: app.workspaceStore.activeWorkspacePaths,
            excludedPaths: app.workspaceStore.activeExcludedPaths,
            openFiles: app.openFilesStore.openFilesForContext(),
            activeFilePath: app.openFilesStore.openFilePath,
            activeRootPath: app.workspaceStore.activeWorkspacePaths.first?.path
        )
    }
}
