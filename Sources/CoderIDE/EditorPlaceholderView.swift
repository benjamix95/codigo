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
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text(fileDisplayName(path))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5))

            Rectangle().fill(DesignSystem.Colors.border).frame(height: 0.5)

            if let error = loadError {
                Text(error).font(.caption).foregroundStyle(DesignSystem.Colors.error).padding(12)
            } else {
                TextEditor(text: .constant(fileContent))
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(DesignSystem.Colors.backgroundPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(DesignSystem.Colors.borderAccent)

            VStack(spacing: 10) {
                Text("Editor")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                if displayPath.isEmpty {
                    Text("Apri un progetto o workspace dalla sidebar per iniziare")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        Text(folderPaths.count > 1 ? "PROGETTO ATTIVO" : "WORKSPACE ATTIVO")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .tracking(1.2)

                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(folderPaths.count > 1
                                 ? folderPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                                 : displayPath)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5))
                    }

                    Text("Seleziona un file dalla sidebar per visualizzarlo")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }

            if !displayPath.isEmpty {
                HStack(spacing: 20) {
                    featureHint("Naviga file", "folder")
                    featureHint("Cerca", "magnifyingglass")
                    featureHint("Modifica", "pencil")
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    private func featureHint(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5))
    }

    private func fileDisplayName(_ path: String) -> String { (path as NSString).lastPathComponent }

    private func loadFile(path: String?) {
        loadError = nil; fileContent = ""
        guard let path = path, !path.isEmpty else { return }
        do { fileContent = try String(contentsOfFile: path, encoding: .utf8) }
        catch { loadError = "Impossibile aprire il file: \(error.localizedDescription)" }
    }
}
