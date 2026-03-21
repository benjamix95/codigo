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
    @Published var indexProgress: IndexingProgress?

    let codebaseIndex = CodebaseIndex()
    lazy var languageService = LanguageService(codebaseIndex: codebaseIndex)

    private(set) var fileWatcher: FileWatcher?
    private(set) var indexingEpoch: UUID = UUID()
    private(set) var progressPollingTask: Task<Void, Never>?
    private(set) var indexingTask: Task<Void, Never>?

    init() {
        load()
    }

    var activeWorkspace: Workspace? {
        guard let id = activeWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }
    }

    var activeWorkspacePaths: [URL] {
        guard let ws = activeWorkspace else { return [] }
        return ws.folderPaths.map { URL(fileURLWithPath: $0) }
    }

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

    var effectiveExcludedPaths: [String] {
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

    func indexActiveWorkspace() {
        let activeToken = resetIndexingInfrastructure()
        let paths = activeWorkspacePaths

        guard isAutomaticIndexingEnabled, !paths.isEmpty else {
            let index = codebaseIndex
            indexingTask = Task(priority: .utility) { [weak self] in
                defer {
                    Task { @MainActor [weak self] in
                        guard self?.indexingEpoch == activeToken else { return }
                        self?.indexingTask = nil
                    }
                }
                guard !Task.isCancelled else { return }
                let isCurrentEpoch = await MainActor.run { self?.indexingEpoch == activeToken }
                guard isCurrentEpoch else { return }
                await index.clear()
            }
            return
        }

        let excluded = indexerExcludedPaths(for: paths, excludedPaths: effectiveExcludedPaths)
        let filePatterns = globalExcludedFilePatterns
        let gitignore = isRespectGitignoreEnabled
        let index = codebaseIndex

        startProgressPolling(activeToken: activeToken)

        indexingTask = Task(priority: .utility) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    guard self?.indexingEpoch == activeToken else { return }
                    self?.indexingTask = nil
                }
            }
            guard !Task.isCancelled else { return }
            let isCurrentEpoch = await MainActor.run { self?.indexingEpoch == activeToken }
            guard isCurrentEpoch else { return }
            let _ = await index.indexWorkspace(
                paths: paths,
                excludedPaths: excluded,
                excludedFilePatterns: filePatterns,
                respectGitignore: gitignore
            )

            guard !Task.isCancelled else { return }
            let stillCurrentEpoch = await MainActor.run { self?.indexingEpoch == activeToken }
            guard stillCurrentEpoch else { return }

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
                DispatchQueue.main.async { [weak self] in
                    guard self?.indexingEpoch == activeToken else { return }
                    self?.indexProgress = nil
                }
            }
        }
    }

    private func startProgressPolling(activeToken: UUID) {
        let index = codebaseIndex
        progressPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self?.indexingEpoch == activeToken else { break }
                let info = await index.status()
                guard !Task.isCancelled else { break }
                DispatchQueue.main.async { [weak self] in
                    guard self?.indexingEpoch == activeToken else { return }
                    self?.indexProgress = info.progress
                }
                if info.status != .indexing { break }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func resetIndexingInfrastructure() -> UUID {
        indexingEpoch = UUID()
        indexingTask?.cancel()
        indexingTask = nil
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
}
