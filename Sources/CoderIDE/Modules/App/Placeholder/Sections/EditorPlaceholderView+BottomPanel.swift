import SwiftUI

extension EditorPlaceholderView {
    var bottomPanelView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                bottomPanelTab(.problems, title: "Problems")
                bottomPanelTab(.references, title: "References")
                bottomPanelTab(.outline, title: "Outline")
                Spacer()
                Button {
                    editorPanelsStore.hideBottomPanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.backgroundPrimary.opacity(0.85))

            Divider().opacity(0.2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    switch editorPanelsStore.activeBottomPanel {
                    case .problems:
                        problemsPanelRows
                    case .references:
                        referencesPanelRows
                    case .outline:
                        outlinePanelRows
                    case .none:
                        EmptyView()
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(DesignSystem.Colors.backgroundDeep)
    }

    private func bottomPanelTab(_ panel: EditorBottomPanel, title: String) -> some View {
        let active = editorPanelsStore.activeBottomPanel == panel
        return Button {
            editorPanelsStore.showBottomPanel(panel)
            if panel == .outline {
                refreshOutline(for: activeEditorPath)
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    active ? Color.accentColor.opacity(0.12) : .clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var problemsPanelRows: some View {
        Group {
            if editorDiagnosticsStore.allDiagnostics.isEmpty {
                bottomPanelPlaceholder("No diagnostics")
            } else {
                ForEach(editorDiagnosticsStore.allDiagnostics) { diagnostic in
                    Button {
                        navigateTo(path: diagnostic.filePath, line: diagnostic.line)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(diagnostic.severity == .error ? DesignSystem.Colors.error : DesignSystem.Colors.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagnostic.message)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("\((diagnostic.filePath as NSString).lastPathComponent):\(diagnostic.line)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var referencesPanelRows: some View {
        Group {
            if editorSymbolsStore.references.isEmpty {
                bottomPanelPlaceholder("No references")
            } else {
                ForEach(editorSymbolsStore.references) { reference in
                    Button {
                        navigateTo(path: reference.filePath, line: reference.line)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reference.symbolName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("\((reference.filePath as NSString).lastPathComponent):\(reference.line):\(reference.column)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var outlinePanelRows: some View {
        Group {
            let items = editorSymbolsStore.outline(for: activeEditorPath ?? "")
            if items.isEmpty {
                bottomPanelPlaceholder("No symbols indexed")
            } else {
                ForEach(items) { item in
                    Button {
                        if let path = activeEditorPath {
                            navigateTo(path: path, line: item.line)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.iconName)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("L\(item.line) • \(item.detail)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func bottomPanelPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 32)
    }
}
