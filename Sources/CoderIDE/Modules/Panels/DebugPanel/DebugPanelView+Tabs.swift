import SwiftUI
import CoderEngine

extension DebugPanelView {
    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case .logs:       logsContent
        case .runtime:    runtimeLogsContent
        case .hypotheses: hypothesesContent
        case .markers:    markersContent
        case .native:     nativeDebugContent
        }
    }

    // MARK: - Todos Card

    var todosCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 10))
                    .foregroundStyle(accent.opacity(0.7))
                Text("Tasks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                let done = todoStore.todos.filter { $0.status == .done }.count
                Text("\(done)/\(todoStore.todos.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            ForEach(todoStore.todos) { item in
                HStack(spacing: 6) {
                    Image(systemName: todoIcon(item.status))
                        .font(.system(size: 9))
                        .foregroundStyle(todoColor(item.status))
                    Text(item.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(item.status == .done ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                        .strikethrough(item.status == .done)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    func todoIcon(_ status: TodoStatus) -> String {
        switch status {
        case .pending:    return "circle"
        case .inProgress: return "circle.dotted"
        case .done:       return "checkmark.circle.fill"
        case .blocked:    return "exclamationmark.circle"
        }
    }

    func todoColor(_ status: TodoStatus) -> Color {
        switch status {
        case .pending:    return .secondary
        case .inProgress: return accent
        case .done:       return DesignSystem.Colors.success
        case .blocked:    return DesignSystem.Colors.error
        }
    }

    // MARK: - Logs Content

    var logsContent: some View {
        Group {
            if debugStore.filteredLogs.isEmpty {
                emptyState(
                    icon: "doc.text",
                    title: "No logs yet",
                    subtitle: "Debug logs will appear as the agent analyzes the issue"
                )
            } else {
                ForEach(debugStore.filteredLogs) { entry in
                    logRow(entry)
                }
            }
        }
    }

    func logRow(_ entry: DebugLogEntry) -> some View {
        let isExpanded = expandedLogId == entry.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                    expandedLogId = isExpanded ? nil : entry.id
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(entry.severity.color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(entry.source)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)

                            if let cat = entry.category {
                                Text(cat)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.04), in: Capsule())
                            }

                            Spacer()

                            Text(timeString(entry.timestamp))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let detail = entry.detail {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.leading, 22)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            divider.opacity(0.5)
        }
    }

    // MARK: - Hypotheses Content

    var hypothesesContent: some View {
        Group {
            if debugStore.hypotheses.isEmpty {
                emptyState(
                    icon: "lightbulb",
                    title: "No hypotheses yet",
                    subtitle: "The agent will form hypotheses during analysis"
                )
            } else {
                ForEach(debugStore.hypotheses) { h in
                    hypothesisCard(h)
                }
            }
        }
    }

    func hypothesisCard(_ h: DebugHypothesis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(h.status.color.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: h.status.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(h.status.color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(h.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(2)
                    Text(h.status.rawValue.capitalized)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(h.status.color)
                }

                Spacer()
            }

            Text(h.description)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(4)

            if !h.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Evidence")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    ForEach(h.evidence, id: \.self) { ev in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(h.status.color.opacity(0.6))
                                .padding(.top, 3)
                            Text(ev)
                                .font(.system(size: 10))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(h.status.color.opacity(0.15), lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(h.status.color.opacity(0.4))
                .frame(width: 2.5)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Runtime Logs

    var runtimeLogsContent: some View {
        let runtimeEntries = debugStore.currentRunId == nil
            ? debugStore.runtimeLogs
            : debugStore.currentRunLogs

        return Group {
            if runtimeEntries.isEmpty {
                emptyState(
                    icon: "waveform.path.ecg",
                    title: "No runtime logs",
                    subtitle: "Runtime logs appear when the agent instruments code"
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let runId = debugStore.currentRunId {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accent)
                                .frame(width: 6, height: 6)
                            Text("Run \(runId.prefix(8))…")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            Spacer()
                            Text("\(debugStore.currentRunLogs.count) entries")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }

                    ForEach(runtimeEntries) { entry in
                        runtimeLogRow(entry)
                    }
                }
            }
        }
    }

    func runtimeLogRow(_ entry: RuntimeLogEntry) -> some View {
        let isExpanded = expandedRuntimeLogId == entry.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                    expandedRuntimeLogId = isExpanded ? nil : entry.id
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(accent.opacity(0.6))
                        .frame(width: 14)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(isExpanded ? nil : 2)

                        HStack(spacing: 6) {
                            Text(entry.location)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)

                            if let hid = entry.hypothesisId {
                                Text("H:\(hid.prefix(6))")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.warning)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(DesignSystem.Colors.warning.opacity(0.1), in: Capsule())
                            }

                            Spacer()

                            Text(timeString(entry.timestamp))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        }
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && !entry.data.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.data.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(spacing: 4) {
                            Text(key)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(accent)
                            Text("=")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                            Text(value)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.leading, 22)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(accent.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            divider.opacity(0.5)
        }
    }
}
