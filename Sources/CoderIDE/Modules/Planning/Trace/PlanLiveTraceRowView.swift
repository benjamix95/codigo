import SwiftUI

struct PlanLiveTraceRowView: View {
    let item: PlanTraceItem
    let workspaceHints: [String]
    let isExpanded: Bool
    let preview: FileChangePreviewResult?
    let isLoadingPreview: Bool
    let expandedOutput: String?
    let timestampText: String
    let onToggleExpanded: () -> Void
    let onOpenFile: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.iconColor)
                    .frame(width: 14)
                Text(item.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .textShimmer(active: item.status == .running)
                Spacer()

                if let fileChange = item.fileChange {
                    Text("+\(max(0, fileChange.added))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.success)
                    Text("-\(max(0, fileChange.removed))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.error)
                }

                Text(item.status.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(item.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.status.color.opacity(0.12), in: Capsule())
                Text(timestampText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if let fileChange = item.fileChange,
               let path = fileChange.path,
               !path.isEmpty,
               let openPath = FileChangePreviewResolver.resolveOpenPath(
                for: fileChange,
                workspaceHints: workspaceHints
               ) {
                Button {
                    onOpenFile?(openPath)
                } label: {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.info)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
            } else {
                Text(item.displaySummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textShimmer(active: item.status == .running)
            }

            if item.isExpandable {
                Button {
                    onToggleExpanded()
                } label: {
                    Text(isExpanded ? "Hide output" : "Show output")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.info)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                expandedContent
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension PlanLiveTraceRowView {
    @ViewBuilder
    var expandedContent: some View {
        if item.fileChange != nil {
            if isLoadingPreview {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading preview...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else if let preview {
                Text(preview.text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
        } else if let expandedOutput {
            Text(expandedOutput)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
    }
}
