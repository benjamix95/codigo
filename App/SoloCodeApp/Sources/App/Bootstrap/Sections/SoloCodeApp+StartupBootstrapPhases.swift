import Foundation
import CoderEngine

extension SoloCodeApp {
    @MainActor
    func configureCriticalStartupServices() {
        bootstrapPersistenceIfNeeded()
        FontPreferences.registerBundledFonts()
        registerCoreProviders()
        pipelineIntegrationService.configure(
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            executionController: executionController
        )
        gitPanelStore.postCommitBugHunterObserver = { commit, gitRoot in
            Task { @MainActor in
                self.enqueueBugHunterPostCommit(
                    commit: commit,
                    gitRoot: gitRoot,
                    triggerKind: .appCommit
                )
            }
        }
        startCodeReviewCommandLoopIfNeeded()
        startBugHunterCommandLoopIfNeeded()
        installDraftFlushTerminationObserver()
    }

    @MainActor
    func scheduleDeferredStartupServices() {
        let workspacePaths = workspaceStore.activeWorkspacePaths.map(\.path)

        Task(priority: .utility) {
            SoloCodeSkillsPolicySource.ensureSkillsDirectoryExists()
        }
        Task(priority: .utility) {
            SoloCodeSkillsPolicySource.ensureProjectSkillsDirectories(
                forWorkspacePaths: workspacePaths
            )
        }

        Task { @MainActor [projectContextStore, workspaceStore, chatStore, planHistoryStore] in
            await Task.yield()
            projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
            workspaceStore.syncActiveWorkspace(with: projectContextStore.activeContext)
            chatStore.migrateLegacyContextsIfNeeded(
                contextStore: projectContextStore,
                workspaceStore: workspaceStore
            )
            chatStore.backfillPlanAttachmentsIfNeeded(historyStore: planHistoryStore)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            CLIAccountsStore.shared.bootstrapAccountsIfNeeded()
            CLIAccountRouter.shared.bootstrapActiveSelectionsIfNeeded()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            registerDeferredProviders()
        }

        Task { @MainActor [appUpdateCenter] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await appUpdateCenter.checkForUpdates()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            CodexMCPHealthStore.shared.refresh()
        }
    }

    @MainActor
    private func installDraftFlushTerminationObserver() {
        NotificationCenter.default.addObserver(
            forName: .soloCodeWillTerminateSaveDrafts,
            object: nil,
            queue: .main
        ) { [chatStore] _ in
            MainActor.assumeIsolated {
                chatStore.saveDraftsImmediately()
            }
        }
    }
}
