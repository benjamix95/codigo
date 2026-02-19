import SwiftUI

struct EditorPlaceholderView: View {
    let folderPaths: [String]
    let openFilePath: String?

    private var displayPath: String { folderPaths.first ?? "" }
    @State private var fileContent: String = ""
    @State private var loadError: String?

    var body: some View {
        Group {
            if let path = openFilePath, !path.isEmpty {
                fileEditorView(path: path)
            } else {
                placeholderView
            }
        }
        .onChange(of: openFilePath) { _, newPath in loadFile(path: newPath) }
        .onAppear { loadFile(path: openFilePath) }
    }

    private func fileEditorView(path: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(fileDisplayName(path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if let error = loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(12)
            } else {
                TextEditor(text: .constant(fileContent))
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("Editor")
                    .font(.title2.weight(.semibold))

                if displayPath.isEmpty {
                    Text("Apri un progetto o workspace dalla sidebar per iniziare")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        Text(folderPaths.count > 1 ? "Progetto attivo" : "Workspace attivo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(folderPaths.count > 1
                                 ? folderPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                                 : displayPath)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    Text("Seleziona un file dalla sidebar per visualizzarlo")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }

            if !displayPath.isEmpty {
                HStack(spacing: 24) {
                    featureHint("Naviga file", "folder")
                    featureHint("Cerca", "magnifyingglass")
                    featureHint("Modifica", "pencil")
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureHint(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fileDisplayName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func loadFile(path: String?) {
        loadError = nil
        fileContent = ""
        guard let path = path, !path.isEmpty else { return }
        do {
            fileContent = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            loadError = "Impossibile aprire il file: \(error.localizedDescription)"
        }
    }
}
