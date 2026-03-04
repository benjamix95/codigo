import SwiftUI

// MARK: - Merge Conflict Panel

/// Pannello SwiftUI per la risoluzione visuale dei conflitti di merge.
struct MergeConflictPanel: View {
    @State private var conflictedFiles: [String] = []
    @State private var selectedFile: String?
    @State private var parseResult: MergeConflictParser.ParseResult?
    @State private var isLoading = false

    let workspacePath: String
    private let service = MergeConflictService()

    var body: some View {
        VStack(spacing: 0) {
            conflictToolbar
            Divider()
            if isLoading {
                ProgressView("Ricerca conflitti...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if conflictedFiles.isEmpty {
                noConflictsView
            } else {
                HSplitView {
                    fileList.frame(minWidth: 180, maxWidth: 250)
                    conflictDetail
                }
            }
        }
        .task { await refreshConflicts() }
    }

    // MARK: - Toolbar

    private var conflictToolbar: some View {
        HStack {
            Text("Conflitti di Merge")
                .font(.headline)
            Spacer()
            Button(action: { Task { await refreshConflicts() } }) {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            Text("\(conflictedFiles.count) file")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - File List

    private var fileList: some View {
        List(conflictedFiles, id: \.self, selection: $selectedFile) { file in
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text((file as NSString).lastPathComponent)
                    .font(.system(.callout, design: .monospaced))
            }
        }
        .onChange(of: selectedFile) { _, newFile in
            if let path = newFile {
                parseResult = MergeConflictParser.parse(filePath: path)
            }
        }
    }

    // MARK: - Conflict Detail

    private var conflictDetail: some View {
        Group {
            if let result = parseResult, result.hasConflicts {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(result.hunks) { hunk in
                            conflictHunkView(hunk, filePath: result.filePath)
                        }
                    }
                    .padding()
                }
            } else {
                Text("Seleziona un file con conflitti")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func conflictHunkView(
        _ hunk: MergeConflictParser.ConflictHunk,
        filePath: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conflitto righe \(hunk.startLine)-\(hunk.endLine)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                // Ours
                VStack(alignment: .leading) {
                    Text("Ours (\(hunk.oursLabel))").font(.caption).bold()
                    Text(hunk.oursContent)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
                .frame(maxWidth: .infinity)

                // Theirs
                VStack(alignment: .leading) {
                    Text("Theirs (\(hunk.theirsLabel))").font(.caption).bold()
                    Text(hunk.theirsContent)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                resolveButton("Accetta Ours", resolution: .ours, hunk: hunk, filePath: filePath)
                resolveButton("Accetta Theirs", resolution: .theirs, hunk: hunk, filePath: filePath)
                resolveButton("Accetta Entrambi", resolution: .both, hunk: hunk, filePath: filePath)
            }
            Divider()
        }
    }

    private func resolveButton(
        _ label: String,
        resolution: ConflictResolution,
        hunk: MergeConflictParser.ConflictHunk,
        filePath: String
    ) -> some View {
        Button(label) {
            Task {
                _ = await service.resolveHunk(filePath: filePath, hunk: hunk, resolution: resolution)
                parseResult = MergeConflictParser.parse(filePath: filePath)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var noConflictsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.green)
            Text("Nessun conflitto di merge")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func refreshConflicts() async {
        isLoading = true
        conflictedFiles = await service.findConflictedFiles(workspacePath: workspacePath)
        isLoading = false
    }
}
