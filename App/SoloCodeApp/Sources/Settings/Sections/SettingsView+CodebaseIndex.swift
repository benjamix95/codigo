import SwiftUI
import CoderEngine

// MARK: - CodebaseIndexSettingsSection

struct CodebaseIndexSettingsSection: View {
    @State var indexConfig = SettingsIndexConfig()

    @EnvironmentObject var workspaceStore: WorkspaceStore

    @State private var indexStatusText: String = "Loading..."
    @State private var indexStatsText: String = ""
    @State private var statusRefreshTask: Task<Void, Never>?
    @State private var dbSizeText: String = "Calculating..."
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSectionHeader(title: "Codebase Index", subtitle: "Symbol indexing and semantic search", icon: "text.magnifyingglass")

            automaticIndexingGroup
            indexStatusGroup
            databaseStorageGroup
            vectorSearchGroup
            trigramIndexGroup
            excludedPathsGroup
            respectGitignoreGroup
            excludedFilePatternsGroup
        }
        .onChange(of: indexConfig.codebaseIndexEnabled) { _ in
            workspaceStore.indexActiveWorkspace()
            Task { await refreshIndexStatus() }
        }
        .onChange(of: indexConfig.codebaseIndexExcludedPaths) { _ in
            workspaceStore.indexActiveWorkspace()
        }
        .onAppear {
            Task { await refreshIndexStatus() }
            refreshDbSize()
            statusRefreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { break }
                    await refreshIndexStatus()
                    refreshDbSize()
                }
            }
        }
        .onDisappear {
            statusRefreshTask?.cancel()
            statusRefreshTask = nil
        }
    }

    // MARK: - Refresh Logic

    private func refreshIndexStatus() async {
        let index = workspaceStore.codebaseIndex
        let info = await index.status()
        switch info.status {
        case .idle: indexStatusText = "Idle - no indexed workspace"
        case .indexing: indexStatusText = "Indexing..."
        case .ready:
            let duration = info.indexDurationMs > 0 ? " (\(info.indexDurationMs)ms)" : ""
            indexStatusText = "Ready\(duration)"
        case .error: indexStatusText = "Indexing error"
        }
        var stats: [String] = []
        if info.totalFiles > 0 { stats.append("\(info.totalFiles) files") }
        if info.totalSourceFiles > 0 { stats.append("\(info.totalSourceFiles) sources") }
        if info.totalSymbols > 0 { stats.append("\(info.totalSymbols) symbols") }
        indexStatsText = stats.joined(separator: " · ")
    }

    private func refreshDbSize() {
        let bytes = ManagedPostgresService.shared.dataDirSizeBytes()
        dbSizeText = Self.formattedSize(bytes)
    }

    static func formattedSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Subviews

private extension CodebaseIndexSettingsSection {
    var automaticIndexingGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Automatic indexing", isOn: $indexConfig.codebaseIndexEnabled).toggleStyle(.switch)
                settingsHintBox("When enabled, the active workspace is indexed automatically on startup. The index provides symbol search, navigation, and context to AI providers.")
            }
        }
    }

    var indexStatusGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingsFieldLabel("Index status")

                HStack(spacing: 12) {
                    // Circular progress badge (same component as sidebar).
                    IndexCircleBadge(progress: workspaceStore.indexProgress)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        if let progress = workspaceStore.indexProgress {
                            Text("Indexing \(progress.percentText)")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("\(progress.current)/\(progress.total) files")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(indexStatusText)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                            if !indexStatsText.isEmpty {
                                Text(indexStatsText)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()
                }

                if let progress = workspaceStore.indexProgress {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }

                Button("Reindex") {
                    Task {
                        indexStatusText = "Reindexing..."
                        workspaceStore.indexActiveWorkspace()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(workspaceStore.indexProgress != nil)
            }
        }
    }

    var databaseStorageGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingsFieldLabel("Database storage")

                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.secondary)
                    Text(dbSizeText)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Index", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(workspaceStore.indexProgress != nil)
                }

                settingsHintBox("Vector database stored in ~/Library/Application Support/CoderIDE/postgres. Deleting removes all indexed data — it will be rebuilt on next indexing.")
            }
        }
        .alert("Delete vector database?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task.detached(priority: .userInitiated) {
                    try? ManagedPostgresService.shared.deleteDatabase()
                    await MainActor.run {
                        dbSizeText = "0 bytes"
                    }
                }
            }
        } message: {
            Text("This will stop Postgres, delete all indexed data, and free disk space. The index will be rebuilt automatically on next workspace open.")
        }
    }

    var vectorSearchGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Vector Search", isOn: $indexConfig.vectorSearchEnabled)
                    .toggleStyle(.switch)
                settingsHintBox("Semantic code search powered by local embeddings. Everything runs on-device — no data leaves your machine.")
            }
        }
    }

    var trigramIndexGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Instant Grep Index", isOn: $indexConfig.trigramIndexEnabled)
                    .toggleStyle(.switch)
                settingsHintBox("Trigram inverted index for instant grep. Drops search time from seconds to milliseconds on large codebases.")
            }
        }
    }

    var excludedPathsGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingsFieldLabel("Excluded paths")
                TextField("node_modules, .git, build, dist", text: $indexConfig.codebaseIndexExcludedPaths).textFieldStyle(.roundedBorder)
                settingsHintBox("Comma-separated list of directories to exclude. Default directories (node_modules, .git, build, etc.) are always excluded.")
            }
        }
    }

    var respectGitignoreGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Respect .gitignore", isOn: $indexConfig.codebaseIndexRespectGitignore)
                    .toggleStyle(.switch)
                    .onChange(of: indexConfig.codebaseIndexRespectGitignore) { _ in
                        workspaceStore.indexActiveWorkspace()
                    }
                settingsHintBox("When enabled, files and directories listed in .gitignore are excluded from indexing.")
            }
        }
    }

    var excludedFilePatternsGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingsFieldLabel("Excluded file patterns")
                TextField("*.generated.swift, *.pb.swift, *.min.js", text: $indexConfig.codebaseIndexExcludedFilePatterns)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: indexConfig.codebaseIndexExcludedFilePatterns) { _ in
                        // Debounce: only re-index after a short pause
                    }
                settingsHintBox("Comma-separated glob patterns for files to exclude (e.g. *.generated.swift, *.pb.swift).")
                Button("Apply") {
                    workspaceStore.indexActiveWorkspace()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
