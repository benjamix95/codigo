import SwiftUI

extension SettingsView {
    var codebaseIndexSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Codebase Index", subtitle: "Symbol indexing and semantic search", icon: "text.magnifyingglass")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Automatic indexing", isOn: $codebaseIndexEnabled).toggleStyle(.switch)
                    hintBox("When enabled, the active workspace is indexed automatically on startup. The index provides symbol search, navigation, and context to AI providers.")
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Index status")
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

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Excluded paths")
                    TextField("node_modules, .git, build, dist", text: $codebaseIndexExcludedPaths).textFieldStyle(.roundedBorder)
                    hintBox("Comma-separated list of directories to exclude. Default directories (node_modules, .git, build, etc.) are always excluded.")
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Respect .gitignore", isOn: $codebaseIndexRespectGitignore)
                        .toggleStyle(.switch)
                        .onChange(of: codebaseIndexRespectGitignore) {
                            workspaceStore.indexActiveWorkspace()
                        }
                    hintBox("When enabled, files and directories listed in .gitignore are excluded from indexing.")
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Excluded file patterns")
                    TextField("*.generated.swift, *.pb.swift, *.min.js", text: $codebaseIndexExcludedFilePatterns)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: codebaseIndexExcludedFilePatterns) {
                            // Debounce: only re-index after a short pause
                        }
                    hintBox("Comma-separated glob patterns for files to exclude (e.g. *.generated.swift, *.pb.swift).")
                    Button("Apply") {
                        workspaceStore.indexActiveWorkspace()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
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
}
