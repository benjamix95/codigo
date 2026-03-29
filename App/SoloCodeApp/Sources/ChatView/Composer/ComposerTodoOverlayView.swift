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

    var metrics: ChatTodoExecutionCardMetrics {
        ChatTodoExecutionCardMetrics.build(items: items, fileChanges: fileChanges)
    }

    @State var isFileListExpanded = false

    var latestPreviewableFileChange: ToolTraceFileChange? {
        fileChanges.latestPreviewableChange()
    }

    /// Sfondo opaco allineato al grigio del composer: evita che la lista todo in chat trapeli dal gradient semi-trasparente.
    private var opaqueComposerChromeFill: Color {
        isIDEStyle
            ? Color(red: 34 / 255, green: 34 / 255, blue: 36 / 255)
            : Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
    }

    // MARK: - Body

    var body: some View {
        if hasActiveTodos {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(width: 0, height: 0)
                    .onAppear {
                        // #region agent log
                        PlanFlowDebugNDJSONLog.append(
                            hypothesisId: "J",
                            location: "ComposerTodoOverlayView.body",
                            message: "composer_todo_overlay_visible",
                            data: [
                                "itemsCount": String(items.count),
                                "activeNonDoneCount": String(
                                    items.filter { $0.status != .done && !$0.isOperationalPlaceholder }.count
                                ),
                            ]
                        )
                        // #endregion
                    }
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

                    if let latestPreviewableFileChange {
                        Divider().overlay(Color.primary.opacity(0.06))
                        liveDiffPreviewSection(change: latestPreviewableFileChange)
                    }

                    if isFileListExpanded {
                        fileListSection
                    }
                }

                Divider().overlay(Color.primary.opacity(0.08))
            }
            .background(
                RoundedRectangle(cornerRadius: isIDEStyle ? 10 : 12, style: .continuous)
                    .fill(opaqueComposerChromeFill)
            )
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
        // Sopra ScrollView/checklist: evita che hit-testing resti “bloccato” dopo expand.
        .zIndex(2)
    }

    // MARK: - Micro Status

    private func microStatusRow(text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DesignSystem.Colors.planColor.opacity(0.85))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
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
