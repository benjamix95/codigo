import SwiftUI
import CoderEngine

private let workspacesKey = "CoderIDE.workspaces"
private let activeWorkspaceIdKey = "CoderIDE.activeWorkspaceId"
private let codebaseIndexEnabledKey = "codebase_index_enabled"
private let codebaseIndexExcludedPathsKey = "codebase_index_excluded_paths"
private let codebaseIndexRespectGitignoreKey = "codebase_index_respect_gitignore"
private let codebaseIndexExcludedFilePatternsKey = "codebase_index_excluded_file_patterns"

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var workspaces: [Workspace] = []
    @Published var activeWorkspaceId: UUID?

    /// Indexing progress (nil when not indexing)
    @Published var indexProgress: IndexingProgress?

    /// Shared codebase index — available to all providers
    let codebaseIndex = CodebaseIndex()

    /// Language service facade (SourceKit-LSP + local index fallback)
    lazy var languageService = LanguageService(codebaseIndex: codebaseIndex)

    /// File watcher for real-time index updates
    private var fileWatcher: FileWatcher?

    /// Incremented every time workspace indexing is reinitialized.
    /// Older async tasks capture this token and no-op if stale.
    private var indexingEpoch: UUID = UUID()

    /// Progress polling task
    private var progressPollingTask: Task<Void, Never>?

    init() {
        load()
    }

    var activeWorkspace: Workspace? {
        guard let id = activeWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }
    }

    /// Workspace folder URLs for the active workspace
    var activeWorkspacePaths: [URL] {
        guard let ws = activeWorkspace else { return [] }
        return ws.folderPaths.map { URL(fileURLWithPath: $0) }
    }

    /// Active workspace excluded paths
    var activeExcludedPaths: [String] {
        activeWorkspace?.excludedPaths ?? []
    }

    private var isAutomaticIndexingEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: codebaseIndexEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: codebaseIndexEnabledKey)
    }

    private var globalExcludedPaths: [String] {
        let raw = UserDefaults.standard.string(forKey: codebaseIndexExcludedPathsKey) ?? ""
        return normalizedWorkspacePathsCSV(raw)
    }

    private var effectiveExcludedPaths: [String] {
        normalizedWorkspacePaths(activeExcludedPaths + globalExcludedPaths)
    }

    private var isRespectGitignoreEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: codebaseIndexRespectGitignoreKey) == nil {
            return true
        }
        return defaults.bool(forKey: codebaseIndexRespectGitignoreKey)
    }

    private var globalExcludedFilePatterns: [String] {
        let raw = UserDefaults.standard.string(forKey: codebaseIndexExcludedFilePatternsKey) ?? ""
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Index the active workspace (called on workspace change)
    func indexActiveWorkspace() {
        let activeToken = resetIndexingInfrastructure()
        let paths = activeWorkspacePaths

        guard isAutomaticIndexingEnabled, !paths.isEmpty else {
            let index = codebaseIndex
            Task.detached(priority: .utility) {
                await index.clear()
            }
            return
        }

        let excluded = effectiveExcludedPaths
        let filePatterns = globalExcludedFilePatterns
        let gitignore = isRespectGitignoreEnabled
        let index = codebaseIndex

        // Start progress polling
        startProgressPolling(activeToken: activeToken)

        Task.detached(priority: .utility) {
            let _ = await index.indexWorkspace(
                paths: paths,
                excludedPaths: excluded,
                excludedFilePatterns: filePatterns,
                respectGitignore: gitignore
            )

            let isCurrentEpoch = await MainActor.run { self.indexingEpoch == activeToken }
            guard isCurrentEpoch else { return }

            // Start file watcher for real-time updates
            let watcher = FileWatcher(index: index, workspacePaths: paths)
            await watcher.start()
            await MainActor.run { [weak self] in
                guard self?.indexingEpoch == activeToken else {
                    Task { await watcher.stop() }
                    return
                }
                self?.fileWatcher = watcher
                self?.progressPollingTask?.cancel()
                self?.progressPollingTask = nil
                self?.indexProgress = nil
            }
        }
    }

    /// Poll codebase index progress at 300ms intervals
    private func startProgressPolling(activeToken: UUID) {
        let index = codebaseIndex
        progressPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self?.indexingEpoch == activeToken else { break }
                let info = await index.status()
                guard !Task.isCancelled else { break }
                self?.indexProgress = info.progress
                if info.status != .indexing { break }
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            }
        }
    }

    /// Fully reset indexer runtime state and return the active token for this generation.
    /// This avoids stale async tasks from previous workspaces mutating new state.
    private func resetIndexingInfrastructure() -> UUID {
        indexingEpoch = UUID()
        if let watcher = fileWatcher {
            Task { await watcher.stop() }
        }
        fileWatcher = nil
        progressPollingTask?.cancel()
        progressPollingTask = nil
        indexProgress = nil
        return indexingEpoch
    }

    func load() {
        var normalizedPersistedPaths = false
        if let data = UserDefaults.standard.data(forKey: workspacesKey),
           let decoded = try? JSONDecoder().decode([Workspace].self, from: data) {
            workspaces = decoded
            normalizedPersistedPaths = normalizePersistedWorkspacePaths()
        }
        if let idStr = UserDefaults.standard.string(forKey: activeWorkspaceIdKey),
           let id = UUID(uuidString: idStr) {
            activeWorkspaceId = workspaces.contains { $0.id == id } ? id : nil
        }
        if normalizedPersistedPaths {
            save()
        }
        indexActiveWorkspace()
    }

    func setActive(id: UUID?) {
        activeWorkspaceId = id
        save()
        indexActiveWorkspace()
    }

    func save() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: workspacesKey)
        }
        if let id = activeWorkspaceId {
            UserDefaults.standard.set(id.uuidString, forKey: activeWorkspaceIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeWorkspaceIdKey)
        }
    }
    
    /// Create an empty workspace (without folders)
    func createEmpty(name: String) {
        let ws = Workspace(name: name, folderPaths: [])
        workspaces.append(ws)
        if activeWorkspaceId == nil {
            activeWorkspaceId = ws.id
        }
        save()
    }

    /// Create a workspace with a single root folder (convenience)
    func create(name: String, rootPath: String) {
        let ws = normalizedWorkspace(Workspace(name: name, rootPath: rootPath))
        workspaces.append(ws)
        if activeWorkspaceId == nil {
            activeWorkspaceId = ws.id
        }
        save()
    }
    
    /// Aggiunge cartella al workspace
    func addFolder(to workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        guard addNormalizedWorkspacePath(path, to: &workspaces[idx].folderPaths) else { return }
        save()
        if workspaceId == activeWorkspaceId { indexActiveWorkspace() }
    }

    /// Rimuove cartella dal workspace
    func removeFolder(from workspaceId: UUID, path: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        guard removeNormalizedWorkspacePath(path, from: &workspaces[idx].folderPaths) else { return }
        save()
        if workspaceId == activeWorkspaceId { indexActiveWorkspace() }
    }

    func update(_ workspace: Workspace) {
        guard let idx = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[idx] = normalizedWorkspace(workspace)
        save()
        if workspace.id == activeWorkspaceId { indexActiveWorkspace() }
    }

    func delete(id: UUID) {
        let requestedId = id
        workspaces.removeAll { $0.id == id }

        let activeStillExists = activeWorkspaceId.flatMap { current in
            workspaces.contains { $0.id == current }
        } ?? false

        if activeWorkspaceId == requestedId || !activeStillExists {
            activeWorkspaceId = workspaces.first?.id
        }

        save()
        indexActiveWorkspace()
    }

    #if DEBUG
    struct DebugIndexingState: Equatable {
        let activeWorkspaceId: UUID?
        let hasWatcher: Bool
        let hasProgressPollingTask: Bool
        let indexingEpoch: UUID
    }

    func debugIndexingState() -> DebugIndexingState {
        DebugIndexingState(
            activeWorkspaceId: activeWorkspaceId,
            hasWatcher: fileWatcher != nil,
            hasProgressPollingTask: progressPollingTask != nil,
            indexingEpoch: indexingEpoch
        )
    }

    func debugEffectiveExcludedPaths() -> [String] {
        effectiveExcludedPaths
    }
    #endif

}
