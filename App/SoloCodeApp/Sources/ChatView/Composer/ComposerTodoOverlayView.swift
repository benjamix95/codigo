import SwiftUI

func hasVisibleComposerTodoOverlay(items: [TodoItem]) -> Bool {
    items.contains { $0.status != .done && !$0.isOperationalPlaceholder }
}

func composerTodoAutoExpandSignature(items: [TodoItem]) -> String {
    // Conserva l’ordine già stabilito da `resolveComposerTodoItems` / store (niente secondo sort parziale).
    items
        .filter { $0.status != .done && !$0.isOperationalPlaceholder }
        .map { item in
            let planOrder = item.planOrder.map(String.init) ?? "nil"
            return "\(item.id.uuidString)|\(item.status.rawValue)|\(planOrder)"
        }
        .joined(separator: "||")
}

/// Shows a collapsible todo + file-changes card above the composer.
/// Mirrors the visual style of `ChatTodoExecutionCardView` but lives
/// in the composer area and expands upward.
struct ComposerTodoOverlayView: View {
    let items: [TodoItem]
    let fileChanges: [ToolTraceFileChange]
    let microStatusText: String?
    let isStreaming: Bool
    let isIDEStyle: Bool
    @Binding var isExpanded: Bool
    let onReviewChanges: () -> Void
    /// Solo tap sull’header: `true` dopo expand, `false` dopo collapse (non chiamato per auto-expand da parent).
    var onUserExpandedAfterHeaderTap: ((Bool) -> Void)? = nil
    var isPlanningNextMoveInteractive: Bool = false
    var onPlanningNextMoveTap: (() -> Void)? = nil

    // MARK: - Derived

    private var hasActiveTodos: Bool {
        hasVisibleComposerTodoOverlay(items: items)
    }

    private var metrics: ChatTodoExecutionCardMetrics {
        ChatTodoExecutionCardMetrics.build(items: items, fileChanges: fileChanges)
    }

    @State private var isFileListExpanded = false

    // MARK: - Body

    var body: some View {
        if hasActiveTodos {
            VStack(alignment: .leading, spacing: 0) {
                header

                if let microStatusText, !microStatusText.isEmpty {
                    Divider().overlay(Color.primary.opacity(0.08))
                    if isPlanningNextMoveInteractive, let onTap = onPlanningNextMoveTap {
                        Button(action: onTap) {
                            microStatusRow(text: microStatusText)
                        }
                        .buttonStyle(.plain)
                        .help(
                            "Avvia il prossimo todo del piano o, se l’agente è fermo, invia un promemoria per proseguire."
                        )
                    } else {
                        microStatusRow(text: microStatusText)
                    }
                }

                checklistContainer

                if metrics.fileCount > 0 {
                    Divider().overlay(Color.primary.opacity(0.08))
                    footer

                    if isFileListExpanded {
                        fileListSection
                    }
                }

                Divider().overlay(Color.primary.opacity(0.08))
            }
        }
    }

    @ViewBuilder
    private var checklistContainer: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                Divider().overlay(Color.primary.opacity(0.08))
                checklistSection
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            isExpanded.toggle()
            onUserExpandedAfterHeaderTap?(isExpanded)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(metrics.doneCount) su \(metrics.totalCount) attività completate")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Image(systemName: isExpanded
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Micro Status

    private func microStatusRow(text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .lineLimit(1)
                .textShimmer(active: isStreaming)
            if isPlanningNextMoveInteractive {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Footer (file changes)

    private var footer: some View {
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

    // MARK: - File List (expandable)

    private var fileListSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(fileChanges) { file in
                let displayPath = file.path ?? file.basename
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
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 6)
        .frame(maxHeight: 200)
    }

    private func fileIcon(for path: String) -> String {
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

    // MARK: - Checklist

    private var checklistSection: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, todo in
                    HStack(alignment: .top, spacing: 12) {
                        statusIcon(for: todo.status)
                            .padding(.top, 2)
                        Text("\(index + 1).")
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(todo.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(todo.status == .done ? .secondary : .primary)
                            .strikethrough(todo.status == .done, color: .primary.opacity(0.18))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: 280)
    }

    // MARK: - Status Icon

    @ViewBuilder
    private func statusIcon(for status: TodoStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.5))
        case .inProgress:
            Image(systemName: "circle.inset.filled")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.75))
        case .blocked:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.72))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.success.opacity(0.9))
        }
    }
}
