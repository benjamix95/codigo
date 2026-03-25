import SwiftUI
import CoderEngine

// MARK: - CodebaseIndexSettingsSection

struct CodebaseIndexSettingsSection: View {
    @State var indexConfig = SettingsIndexConfig()

    @EnvironmentObject var workspaceStore: WorkspaceStore

    @State private var indexStatusText: String = "Loading..."
    @State private var indexStatsText: String = ""
    @State private var statusRefreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSectionHeader(title: "Codebase Index", subtitle: "Symbol indexing and semantic search", icon: "text.magnifyingglass")

            automaticIndexingGroup
            indexStatusGroup
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
            statusRefreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { break }
                    await refreshIndexStatus()
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
                if let progress = workspaceStore.indexProgress {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Indexing... \(progress.current)/\(progress.total) files (\(progress.percentText))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                } else {
                    Text(indexStatusText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !indexStatsText.isEmpty && workspaceStore.indexProgress == nil {
                    Text(indexStatsText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    var vectorSearchGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Vector Search", isOn: $indexConfig.vectorSearchEnabled)
                    .toggleStyle(.switch)
                settingsHintBox("Semantic search using local CoreML embeddings. Everything runs locally — no data leaves your machine.")
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
