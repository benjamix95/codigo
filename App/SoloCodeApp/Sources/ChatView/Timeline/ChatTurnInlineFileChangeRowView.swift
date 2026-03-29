import SwiftUI

struct ChatTurnInlineFileChangeRowView: View {
    let change: ToolTraceFileChange
    let openPath: String?
    let showsRunningChrome: Bool
    let isError: Bool
    let isWarning: Bool
    let onOpenFile: (String) -> Void

    private var actionLabel: String {
        switch change.kind {
        case .created:
            return "File creato"
        case .deleted:
            return "File eliminato"
        case .edited, .unknown:
            return "Modifica apportata"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 7) {
                WorkspaceCatalogToolIcon.fileChangeIcon(for: change.kind)
                    .frame(width: 14, alignment: .center)

                Text(actionLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)

                if let openPath {
                    Button {
                        onOpenFile(openPath)
                    } label: {
                        Text(change.basename)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.planColor.opacity(0.95))
                            .lineLimit(1)
                            .textShimmer(active: showsRunningChrome)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(change.basename)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.planColor.opacity(0.95))
                        .lineLimit(1)
                        .textShimmer(active: showsRunningChrome)
                }

                Spacer(minLength: 0)

                if let lineSummary = change.lineSummaryParts {
                    HStack(spacing: 4) {
                        if lineSummary.added > 0 {
                            Text("+\(lineSummary.added)")
                                .foregroundStyle(DesignSystem.Colors.success)
                        }
                        if lineSummary.removed > 0 {
                            Text("-\(lineSummary.removed)")
                                .foregroundStyle(DesignSystem.Colors.error)
                        }
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                }

                if showsRunningChrome {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else if isError {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.error)
                } else if isWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.warning)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.success.opacity(0.8))
                }
            }

            ToolTraceFileChangeCompactPreviewView(
                change: change,
                maxLines: showsRunningChrome ? 4 : 3,
                showsBackground: true,
                compactPadding: 8
            )
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.26))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.9), lineWidth: 0.5)
        )
    }
}

private extension WorkspaceCatalogToolIcon {
    static func fileChangeIcon(for kind: ToolTraceFileChangeKind) -> some View {
        let symbolName: String
        let tint: Color

        switch kind {
        case .created:
            symbolName = "plus.square.fill"
            tint = DesignSystem.Colors.success
        case .deleted:
            symbolName = "minus.square.fill"
            tint = DesignSystem.Colors.error
        case .edited, .unknown:
            symbolName = "square.and.pencil"
            tint = DesignSystem.Colors.planColor
        }

        return Image(systemName: symbolName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
    }
}

private extension ToolTraceFileChange {
    var lineSummaryParts: (added: Int, removed: Int)? {
        guard added > 0 || removed > 0 else { return nil }
        return (added, removed)
    }
}
