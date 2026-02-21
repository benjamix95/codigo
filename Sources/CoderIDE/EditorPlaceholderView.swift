import SwiftUI
import CodeEditorView
import LanguageSupport

struct EditorPlaceholderView: View {
    let folderPaths: [String]
    @EnvironmentObject var openFilesStore: OpenFilesStore

    private var displayPath: String { folderPaths.first ?? "" }
    @State private var saveFeedback: String?
    @State private var saveFeedbackIsError = false

    @State private var position: CodeEditor.Position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = []

    var body: some View {
        Group {
            if let path = openFilesStore.openFilePath, !path.isEmpty {
                fileEditorView(path: path)
            } else {
                placeholderView
            }
        }
        .onChange(of: openFilesStore.openFilePath) { _, newPath in
            openFilesStore.ensureLoaded(newPath)
            position = CodeEditor.Position()
            messages = []
            saveFeedback = nil
            saveFeedbackIsError = false
        }
        .onAppear { openFilesStore.ensureLoaded(openFilesStore.openFilePath) }
    }

    private func fileEditorView(path: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            openFilesTabBar
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text(fileDisplayName(path))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if openFilesStore.isDirty(path: path) {
                    Text("Modificato")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DesignSystem.Colors.warning.opacity(0.15), in: Capsule())
                }
                Spacer()

                if openFilesStore.diff(for: path) != nil {
                    Picker("", selection: viewModeBinding(path: path)) {
                        Text("File").tag(EditorViewMode.plain)
                        Text("Diff").tag(EditorViewMode.diffInline)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }

                Button {
                    openFilesStore.reload(path: path)
                    saveFeedback = "Ricaricato da disco"
                    saveFeedbackIsError = false
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Ricarica file da disco")

                Button("Salva") {
                    let saved = openFilesStore.save(path: path)
                    if saved {
                        saveFeedback = "Salvato"
                        saveFeedbackIsError = false
                    } else {
                        saveFeedback = openFilesStore.error(for: path) ?? "Errore nel salvataggio"
                        saveFeedbackIsError = true
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!openFilesStore.isDirty(path: path))
                .keyboardShortcut("s", modifiers: [.command])
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5))

            Rectangle().fill(DesignSystem.Colors.border).frame(height: 0.5)

            if let error = openFilesStore.error(for: path) {
                Text(error).font(.caption).foregroundStyle(DesignSystem.Colors.error).padding(12)
            } else {
                if openFilesStore.viewMode(for: path) == .diffInline {
                    diffInlineView(path: path)
                } else {
                    CodeEditor(
                        text: fileBinding(path: path),
                        position: $position,
                        messages: $messages,
                        language: languageFor(path: path)
                    )
                    .environment(\.codeEditorTheme, Theme.defaultDark)
                }
            }

            if let feedback = saveFeedback {
                Rectangle().fill(DesignSystem.Colors.border).frame(height: 0.5)
                Text(feedback)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(saveFeedbackIsError ? DesignSystem.Colors.error : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignSystem.Colors.backgroundSecondary.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var openFilesTabBar: some View {
        if !openFilesStore.openPaths.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(openFilesStore.openPaths, id: \.self) { tabPath in
                        fileTab(path: tabPath)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.35))
            Rectangle().fill(DesignSystem.Colors.border).frame(height: 0.5)
        }
    }

    private func fileTab(path: String) -> some View {
        let isActive = openFilesStore.openFilePath == path
        return HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 10))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
            Text(fileDisplayName(path))
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .leading)
            if openFilesStore.isDirty(path: path) {
                Circle()
                    .fill(DesignSystem.Colors.warning)
                    .frame(width: 5, height: 5)
            }
            Button {
                openFilesStore.closeFile(path)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? Color.accentColor.opacity(0.14) : DesignSystem.Colors.backgroundSecondary.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.28) : DesignSystem.Colors.border, lineWidth: 0.6)
        )
        .onTapGesture {
            openFilesStore.openFile(path)
        }
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

    private func fileBinding(path: String) -> Binding<String> {
        Binding(
            get: { openFilesStore.content(for: path) },
            set: { newValue in
                openFilesStore.updateContent(newValue, for: path)
                saveFeedback = nil
                saveFeedbackIsError = false
            }
        )
    }

    private func languageFor(path: String) -> LanguageConfiguration {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift()
        default: return .none
        }
    }

    private func viewModeBinding(path: String) -> Binding<EditorViewMode> {
        Binding(
            get: { openFilesStore.viewMode(for: path) },
            set: { newMode in
                openFilesStore.setViewMode(newMode, for: path)
            }
        )
    }

    private func diffInlineView(path: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let diff = openFilesStore.diff(for: path) {
                    if diff.isBinary {
                        Text("Binary file changed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else if diff.chunks.isEmpty {
                        Text("Nessuna diff disponibile per questo file")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else {
                        ForEach(Array(diff.chunks.enumerated()), id: \.offset) { _, chunk in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(chunk.header)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color.accentColor.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.accentColor.opacity(0.08))
                                ForEach(Array(chunk.lines.prefix(3000).enumerated()), id: \.offset) { _, line in
                                    diffLineView(line)
                                }
                            }
                            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5))
                        }
                    }
                } else {
                    Text("Diff non caricata")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .padding(8)
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    private func diffLineView(_ line: String) -> some View {
        let prefix = line.first ?? " "
        let bg: Color = {
            switch prefix {
            case "+":
                return DesignSystem.Colors.success.opacity(0.12)
            case "-":
                return DesignSystem.Colors.error.opacity(0.12)
            default:
                return .clear
            }
        }()
        return Text(line.isEmpty ? " " : line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg)
    }
}
