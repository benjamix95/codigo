import SwiftUI

struct ChangedFilesPanelView: View {
    @EnvironmentObject var store: ChangedFilesStore
    let onOpenFile: (String) -> Void
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Files changed")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text("\(store.files.count) files")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("+\(store.totalAdded)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(store.totalRemoved)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.error)
                if let onClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Chiudi pannello")
                }
            }

            HStack(spacing: 8) {
                Button("Refresh") {
                    store.refresh(workingDirectory: store.gitRoot)
                }
                .buttonStyle(.bordered)

                Button("Undo all") {
                    store.undoAll()
                }
                .buttonStyle(.bordered)
                .disabled(store.files.isEmpty)
            }

            if store.files.isEmpty {
                Text("Nessun file modificato")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.files) { file in
                            HStack(spacing: 8) {
                                Button {
                                    onOpenFile(file.path)
                                } label: {
                                    Text(file.path)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Text("+\(file.added)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.success)
                                Text("-\(file.removed)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.error)
                                Text(file.status)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)

                                Button {
                                    store.undo(path: file.path)
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .help("Ripristina file")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            Divider().opacity(0.35)
                        }
                    }
                }
            }

            if let err = store.error, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.error)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 360)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.7), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
