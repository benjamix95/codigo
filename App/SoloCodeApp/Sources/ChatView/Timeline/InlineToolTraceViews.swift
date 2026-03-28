import SwiftUI

// MARK: - Inline Tool Trace Event View

struct InlineToolTraceEventView: View {
    let event: ToolTraceEvent
    var messageIsStreaming: Bool = true
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void

    private var showsRunningChrome: Bool {
        event.isRunning && messageIsStreaming
    }

    private var fileChange: ToolTraceFileChange? {
        ToolTraceFileChangeMapper.from(event: event)
    }

    func primaryTitle() -> String {
        fileChange?.displayTitle ?? event.title
    }

    private var compactDetail: String? {
        if let fileChange {
            if let lineSummary = fileChange.lineSummary {
                return lineSummary
            }
            return fileChange.path ?? fileChange.basename
        }

        let candidates = [
            event.detail,
            event.payload["command"],
            event.payload["query"],
            event.payload["path"],
            event.payload["file"],
            event.payload["tool"],
            event.payload["mcp_tool"],
            event.payload["mcpTool"],
        ]

        for candidate in candidates {
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty, text != event.title {
                return String(text.prefix(140))
            }
        }
        return nil
    }

    private var openPath: String? {
        if let change = fileChange {
            return FileChangePreviewResolver.resolveOpenPath(
                for: change,
                workspaceHints: workspaceHints
            )
        }
        let candidate = event.payload["path"] ?? event.payload["file"] ?? ""
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return candidate
    }

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            WorkspaceCatalogToolIcon(event: event)
                .frame(width: 14, alignment: .center)

            if let openPath {
                Button {
                    onOpenFile(openPath)
                } label: {
                    Text(primaryTitle())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .textShimmer(active: showsRunningChrome)
                }
                .buttonStyle(.plain)
            } else {
                Text(primaryTitle())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .textShimmer(active: showsRunningChrome)
            }

            if let compactDetail, !compactDetail.isEmpty {
                Text(compactDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if showsRunningChrome {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else if MessageToolTraceView.isErrorType(event) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.error)
            } else if MessageToolTraceView.isWarningType(event) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.warning)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.success.opacity(0.8))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.18))
        )
    }
}
