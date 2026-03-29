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
    private enum IndexLaunchMode {
        case startupBootstrap
        case interactive

        var taskPriority: TaskPriority {
            switch self {
            case .startupBootstrap:
                return .background
            case .interactive:
                return .userInitiated
            }
        }

        var progressPollIntervalNs: UInt64 {
            switch self {
            case .startupBootstrap:
                return 1_000_000_000
            case .interactive:
                return 300_000_000
            }
        }
    }

    private static let workspaceManifestQueue = DispatchQueue(
        label: "com.solocode.workspace.manifest",
        qos: .utility
    )

    static var workspaceManifestDirectoryOverrideURL: URL?
    @Published var workspaces: [Workspace] = []
    @Published var activeWorkspaceId: UUID?
    @Published var indexProgress: IndexingProgress?
    @Published var indexBadgeState: WorkspaceIndexBadgeState = .initial

    let codebaseIndex = CodebaseIndex()
    lazy var languageService = LanguageService(codebaseIndex: codebaseIndex)

    private(set) var fileWatcher: FileWatcher?
    private(set) var indexingEpoch: UUID = UUID()
    private(set) var progressPollingTask: Task<Void, Never>?
    private(set) var indexingTask: Task<Void, Never>?
    private var initialIndexBootstrapTask: Task<Void, Never>?
    private var workspaceManifestSyncWorkItem: DispatchWorkItem?
    /// Evita provision CI ripetuti se le root non cambiano.
    private var lastLocalCIProvisionFingerprint: String?

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

    var isAutomaticIndexingEnabled: Bool {
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
        performIndexActiveWorkspace(launchMode: .interactive)
    }

    private func performIndexActiveWorkspace(launchMode: IndexLaunchMode) {
        initialIndexBootstrapTask?.cancel()
        initialIndexBootstrapTask = nil
        let activeToken = resetIndexingInfrastructure()
        let paths = activeWorkspacePaths

        scheduleLocalCIScaffold(for: paths, launchMode: launchMode)

        guard isAutomaticIndexingEnabled, !paths.isEmpty else {
            resetIndexBadgeToIdle()
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

        // Warm start: se l'indice è già persistito su disco, mostriamo 100% (ready)
        // come stato iniziale. Il task in background validerà e aggiornerà solo se necessario.
        // Questo evita il flash 0% → 100% ad ogni avvio con progetto già indicizzato.
        let hasCachedIndex = CodebaseIndex.hasCachedIndex(for: paths)
        if hasCachedIndex {
            indexBadgeState = WorkspaceIndexBadgeState(
                progress: nil,
                status: .ready,
                hasWorkspacePaths: true,
                indexingEnabled: true
            )
        } else {
            indexBadgeState = WorkspaceIndexBadgeState(
                progress: nil,
                status: .indexing,
                hasWorkspacePaths: true,
                indexingEnabled: true
            )
        }

        startProgressPolling(
            activeToken: activeToken,
            intervalNs: launchMode.progressPollIntervalNs
        )

        indexingTask = Task(priority: launchMode.taskPriority) { [weak self] in
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
                    guard let self, self.indexingEpoch == activeToken else { return }
                    Task { await self.finalizeIndexBadgeAfterRun(activeToken: activeToken) }
                }
            }
        }
    }

    private func finalizeIndexBadgeAfterRun(activeToken: UUID) async {
        guard indexingEpoch == activeToken else { return }
        let info = await codebaseIndex.status()
        guard indexingEpoch == activeToken else { return }
        applyIndexStatus(info)
    }

    private func startProgressPolling(activeToken: UUID, intervalNs: UInt64) {
        let index = codebaseIndex
        progressPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let epochOk = await MainActor.run { [weak self] in
                    guard let self else { return false }
                    return self.indexingEpoch == activeToken
                }
                guard epochOk else { break }

                let info = await index.status()
                guard !Task.isCancelled else { break }

                await MainActor.run { [weak self] in
                    guard let self, self.indexingEpoch == activeToken else { return }
                    self.applyIndexStatus(info)
                }

                // Non usare solo `info.status == .indexing`: all’avvio `indexWorkspace` può non aver
                // ancora chiamato `beginIndexingTransaction`, quindi lo stato attore è ancora .idle/.ready
                // e il loop terminerebbe subito (la sidebar resterebbe ferma finché non si apre Settings).
                let shouldContinue = await MainActor.run { [weak self] in
                    guard let self, self.indexingEpoch == activeToken else { return false }
                    if self.indexingTask != nil { return true }
                    return info.status == .indexing
                }
                guard shouldContinue else { break }

                try? await Task.sleep(nanoseconds: intervalNs)
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
        // Se l'indice è già persistito, manteniamo .ready come stato transitorio
        // per evitare un flash 0% prima che performIndexActiveWorkspace imposti lo stato warm.
        let cachedStatus: IndexStatus = CodebaseIndex.hasCachedIndex(for: activeWorkspacePaths) ? .ready : .idle
        indexBadgeState = WorkspaceIndexBadgeState(
            progress: nil,
            status: cachedStatus,
            hasWorkspacePaths: !activeWorkspacePaths.isEmpty,
            indexingEnabled: isAutomaticIndexingEnabled
        )
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
        scheduleWorkspaceManifestSync()
        scheduleInitialIndexActiveWorkspace()
    }

    func setActive(id: UUID?) {
        guard activeWorkspaceId != id else { return }
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
        scheduleWorkspaceManifestSync()
    }

    /// Genera `.github/workflows/solocode-auto-ci.yml` e `scripts/solocode-run-local-ci.sh` in base ai linguaggi rilevati.
    private func scheduleLocalCIScaffold(for paths: [URL], launchMode: IndexLaunchMode) {
        guard !paths.isEmpty else {
            lastLocalCIProvisionFingerprint = nil
            return
        }
        let fingerprint = paths
            .map { $0.standardizedFileURL.path }
            .sorted()
            .joined(separator: "\u{1e}")
        guard fingerprint != lastLocalCIProvisionFingerprint else { return }
        lastLocalCIProvisionFingerprint = fingerprint
        let roots = paths.map { $0.standardizedFileURL }
        let delayNs: UInt64 = launchMode == .startupBootstrap ? 4_000_000_000 : 0
        Task.detached(priority: .background) {
            if delayNs > 0 {
                try? await Task.sleep(nanoseconds: delayNs)
            }
            WorkspaceLocalCIProvisioner.provision(roots: roots)
        }
    }

    private func scheduleInitialIndexActiveWorkspace() {
        initialIndexBootstrapTask?.cancel()
        guard !activeWorkspacePaths.isEmpty else {
            indexActiveWorkspace()
            return
        }

        let expectedWorkspaceId = activeWorkspaceId
        initialIndexBootstrapTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.activeWorkspaceId == expectedWorkspaceId else { return }
            self.initialIndexBootstrapTask = nil
            self.performIndexActiveWorkspace(launchMode: .startupBootstrap)
        }
    }

    private func scheduleWorkspaceManifestSync() {
        guard let directory = workspaceManifestDirectoryURL() else { return }
        let workspacesSnapshot = workspaces
        workspaceManifestSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            Self.syncWorkspaceManifestFiles(
                workspaces: workspacesSnapshot,
                directory: directory
            )
        }
        workspaceManifestSyncWorkItem = workItem
        Self.workspaceManifestQueue.async(execute: workItem)
    }

    private static func syncWorkspaceManifestFiles(workspaces: [Workspace], directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let eligibleWorkspaces = workspaces.filter { !$0.folderPaths.isEmpty }
        var expectedFileNames = Set<String>()

        for workspace in eligibleWorkspaces {
            let filename = workspaceManifestFileName(for: workspace)
            expectedFileNames.insert(filename)
            let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
            let document = WorkspaceFileDocument(workspace: workspace)
            guard let data = try? JSONEncoder().encode(document) else { continue }
            try? data.write(to: fileURL, options: .atomic)
        }

        let existingFiles = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for fileURL in existingFiles where fileURL.pathExtension == "json" {
            guard fileURL.lastPathComponent.hasSuffix(".workspace.json") else { continue }
            if !expectedFileNames.contains(fileURL.lastPathComponent) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func workspaceManifestDirectoryURL() -> URL? {
        if let override = Self.workspaceManifestDirectoryOverrideURL {
            return override
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SoloCode", isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
    }

    private static func workspaceManifestFileName(for workspace: Workspace) -> String {
        let sanitized = workspace.name
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        let base = sanitized.isEmpty ? "workspace" : sanitized
        return "\(base)-\(workspace.id.uuidString.lowercased()).workspace.json"
    }
}
