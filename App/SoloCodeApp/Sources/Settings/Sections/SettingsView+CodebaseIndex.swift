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
        await workspaceStore.refreshIndexBadgeStateAsync()
        let index = workspaceStore.codebaseIndex
        let info = await index.status()
        let st = workspaceStore.indexBadgeState
        switch info.status {
        case .idle:
            indexStatusText = st.hasWorkspacePaths
                ? "In attesa — avvio indicizzazione (codebase + vettoriale)"
                : "Nessun workspace in app"
        case .indexing:
            indexStatusText = "Scansione file, indice semantico e database vettoriale"
        case .ready:
            let duration = info.indexDurationMs > 0 ? " · \(info.indexDurationMs)ms" : ""
            indexStatusText = st.isFullyIndexed
                ? "Tutto indicizzato: simboli, semantic index e PGVector\(duration)"
                : "Pronto\(duration)"
        case .error:
            indexStatusText = "Errore durante l’indicizzazione"
        }
        var stats: [String] = []
        if info.totalFiles > 0 { stats.append("\(info.totalFiles) file") }
        if info.totalSourceFiles > 0 { stats.append("\(info.totalSourceFiles) sorgenti") }
        if info.totalSymbols > 0 { stats.append("\(info.totalSymbols) simboli") }
        indexStatsText = stats.joined(separator: " · ")
    }

    private func refreshDbSize() {
        let pg = ManagedPostgresService.shared.dataDirSizeBytes()
        let cache = CodebaseIndex.indexCacheStorageBytes(for: workspaceStore.activeWorkspacePaths)
        dbSizeText = Self.formattedSize(pg + cache)
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

                let st = workspaceStore.indexBadgeState
                HStack(alignment: .top, spacing: 12) {
                    IndexCircleBadge(state: st, dimension: 22)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(settingsIndexStatusColor(st))
                                .frame(width: 10, height: 10)
                            Text(settingsIndexHeadline(st))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(st.displayPercentText)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(settingsIndexStatusColor(st))

                        Text(indexStatusText)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !indexStatsText.isEmpty {
                            Text(indexStatsText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        if st.shouldShowWaitNotice {
                            Text(
                                "Attendere il 100%: finché l’indicizzazione non è completa, ricerca semantica e contesto vettoriale possono essere incompleti."
                            )
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        } else if st.shouldShowErrorNotice {
                            Text("Si è verificato un errore. Usa Reindex o controlla i permessi sul workspace.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.error)
                        }
                    }

                    Spacer()
                }

                if st.isIndexingActive, let p = st.progress {
                    ProgressView(value: p.fraction)
                        .progressViewStyle(.linear)
                        .tint(.orange)
                } else if st.isFullyIndexed {
                    ProgressView(value: 1.0)
                        .progressViewStyle(.linear)
                        .tint(DesignSystem.Colors.success)
                }

                Button("Reindex") {
                    Task {
                        indexStatusText = "Reindicizzazione…"
                        workspaceStore.indexActiveWorkspace()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(workspaceStore.indexBadgeState.isIndexingActive)
            }
        }
    }

    func settingsIndexStatusColor(_ st: WorkspaceIndexBadgeState) -> Color {
        if !st.indexingEnabled { return .secondary }
        if !st.hasWorkspacePaths { return .secondary }
        if st.shouldShowErrorNotice { return DesignSystem.Colors.error }
        if st.isFullyIndexed { return DesignSystem.Colors.success }
        if st.isIndexingActive { return Color.orange }
        if st.shouldShowWaitNotice { return Color.red.opacity(0.9) }
        return .secondary
    }

    func settingsIndexHeadline(_ st: WorkspaceIndexBadgeState) -> String {
        if !st.indexingEnabled { return "Indice disattivato" }
        if !st.hasWorkspacePaths { return "Nessun workspace" }
        if st.shouldShowErrorNotice { return "Errore" }
        if st.isFullyIndexed { return "Completato" }
        if st.isIndexingActive { return "In corso" }
        if st.shouldShowWaitNotice { return "In attesa" }
        return "Stato"
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
                    .disabled(workspaceStore.indexBadgeState.isIndexingActive)
                }

                settingsHintBox(
                    "Spazio mostrato = PostgreSQL locale (pgvector / embedding) nella cartella dell’app + cache dell’indice semantico (es. semantic.jsonl sotto Cache). Elimina il DB azzera il vettoriale; la cache su disco può richiedere una nuova indicizzazione per rigenerarsi."
                )
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
