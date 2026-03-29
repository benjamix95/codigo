import SwiftUI

extension ComposerTodoOverlayView {
    var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isFileListExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
                Text("\(metrics.fileCount) file modificati")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("+\(metrics.linesAdded)")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(metrics.linesRemoved)")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.error)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isFileListExpanded.toggle()
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("Rivedi modifiche")
                    .font(.system(size: 12.5, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .onTapGesture {
                onReviewChanges()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    func liveDiffPreviewSection(change: ToolTraceFileChange) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.planColor.opacity(0.9))
                Text("Diff live \(change.basename)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer(minLength: 0)
                if let lineSummary = change.lineSummary {
                    Text(lineSummary)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            ToolTraceFileChangeCompactPreviewView(
                change: change,
                maxLines: isStreaming ? 4 : 3,
                showsBackground: true,
                compactPadding: 14
            )
            .padding(.bottom, 10)
        }
    }

    var fileListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(fileChanges) { file in
                let displayPath = file.path ?? file.basename
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: fileIcon(for: displayPath))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .frame(width: 14)
                            Text(displayPath)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("+\(max(0, file.added))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.success)
                        Text("-\(max(0, file.removed))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.error)
                    }

                    ToolTraceFileChangeCompactPreviewView(
                        change: file,
                        maxLines: 3,
                        showsBackground: true,
                        compactPadding: 10
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 6)
        .frame(maxHeight: 260)
    }

    func fileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "chevron.left.forwardslash.chevron.right"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml": return "doc.badge.gearshape"
        case "md", "txt": return "doc.text"
        case "css", "scss": return "paintbrush"
        case "html": return "globe"
        case "rs": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}
