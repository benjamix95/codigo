import SwiftUI

struct EditorPlaceholderView: View {
    let folderPaths: [String]
    let openFilePath: String?
    
    private var displayPath: String {
        folderPaths.first ?? ""
    }
    
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
        .onChange(of: openFilePath) { _, newPath in
            loadFile(path: newPath)
        }
        .onAppear {
            loadFile(path: openFilePath)
        }
    }
    
    // MARK: - File Editor
    private func fileEditorView(path: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // File path header
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "doc.text.fill")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.primary)
                Text(fileDisplayName(path))
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background {
                Rectangle()
                    .fill(Color.white.opacity(0.02))
            }
            
            if let error = loadError {
                Text(error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.error)
                    .padding(DesignSystem.Spacing.md)
            } else {
                TextEditor(text: .constant(fileContent))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(DesignSystem.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Placeholder
    private var placeholderView: some View {
        VStack(spacing: DesignSystem.Spacing.xxl) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.primary,
                            DesignSystem.Colors.primary.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: DesignSystem.Spacing.md) {
                Text("Editor")
                    .font(DesignSystem.Typography.largeTitle.weight(.semibold))
                    .foregroundStyle(.primary)
                
                if displayPath.isEmpty {
                    Text("Apri un progetto o workspace dalla sidebar per iniziare")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundStyle(DesignSystem.Colors.secondary)
                } else {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text(folderPaths.count > 1 ? "Progetto attivo" : "Workspace attivo")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(DesignSystem.Colors.primary)
                            Text(folderPaths.count > 1 ? folderPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ") : displayPath)
                                .font(DesignSystem.Typography.callout.monospaced())
                                .foregroundStyle(DesignSystem.Colors.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(DesignSystem.Spacing.lg)
                        .background(DesignSystem.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.borderSubtle, lineWidth: 1)
                        )
                    }
                    
                    Text("Seleziona un file dalla sidebar per visualizzarlo")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .padding(.top, DesignSystem.Spacing.xs)
                }
            }
            
            if !displayPath.isEmpty {
                HStack(spacing: DesignSystem.Spacing.xxl) {
                    featureHint("Naviga file", "folder")
                    featureHint("Cerca", "magnifyingglass")
                    featureHint("Modifica", "pencil")
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
        .padding(DesignSystem.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func featureHint(_ title: String, _ icon: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.primary.opacity(0.9))
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondary)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
    }
    
    // MARK: - Helpers
    private func fileDisplayName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
    
    private func loadFile(path: String?) {
        loadError = nil
        fileContent = ""
        guard let path = path, !path.isEmpty else { return }
        
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            fileContent = content
        } catch {
            loadError = "Impossibile aprire il file: \(error.localizedDescription)"
        }
    }
}
