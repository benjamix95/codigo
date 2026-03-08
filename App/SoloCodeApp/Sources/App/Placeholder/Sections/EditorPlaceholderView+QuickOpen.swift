import SwiftUI

extension EditorPlaceholderView {
    var quickOpenOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Quick open file...", text: Binding(
                    get: { editorQuickOpenStore.query },
                    set: { editorQuickOpenStore.applyQuery($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13))

                Button {
                    editorPanelsStore.hideQuickOpen()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(DesignSystem.Colors.backgroundSecondary)

            Divider().opacity(0.2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if editorQuickOpenStore.isLoading {
                        quickOpenRow(title: "Indexing workspace files…", detail: nil)
                    } else if editorQuickOpenStore.results.isEmpty {
                        quickOpenRow(title: "No files found", detail: nil)
                    } else {
                        ForEach(editorQuickOpenStore.results) { result in
                            Button {
                                openQuickOpenResult(result)
                            } label: {
                                quickOpenRow(
                                    title: result.fileName,
                                    detail: result.displayPath
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .frame(maxWidth: .infinity)
        .background(
            DesignSystem.Colors.backgroundPrimary,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }

    private func quickOpenRow(title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}
