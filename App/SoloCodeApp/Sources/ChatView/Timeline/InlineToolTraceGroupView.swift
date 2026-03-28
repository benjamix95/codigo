import SwiftUI

struct InlineToolTraceGroupView: View {
    let group: ChatTurnToolEventGroup
    var messageIsStreaming: Bool = true
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void

    @State private var autoPresentationState: InlineToolTraceGroupAutoPresentationState

    init(
        group: ChatTurnToolEventGroup,
        messageIsStreaming: Bool = true,
        workspaceHints: [String],
        onOpenFile: @escaping (String) -> Void
    ) {
        self.group = group
        self.messageIsStreaming = messageIsStreaming
        self.workspaceHints = workspaceHints
        self.onOpenFile = onOpenFile
        _autoPresentationState = State(
            initialValue: InlineToolTraceGroupAutoPresentation.initialState(
                hasRunningEvent: Self.hasEffectiveRunningEvent(
                    events: group.events,
                    messageIsStreaming: messageIsStreaming
                ),
                hasEvents: !group.events.isEmpty
            )
        )
    }

    private var isExpanded: Bool {
        autoPresentationState.isExpanded
    }

    private var hasEvents: Bool {
        !group.events.isEmpty
    }

    private var hasRunningEvent: Bool {
        Self.hasEffectiveRunningEvent(
            events: group.events,
            messageIsStreaming: messageIsStreaming
        )
    }

    private var lifecycleToken: String {
        let eventToken = group.events.map {
            "\($0.id.uuidString.lowercased()):\($0.isRunning ? 1 : 0):\($0.sequence)"
        }.joined(separator: "|")
        return "\(messageIsStreaming ? 1 : 0)#\(eventToken)"
    }

    private var summaryTitle: String {
        switch group.category {
        case .exploration:
            let fileCount = exploredTargets.count
            let searchCount = searchEvents.count
            var parts: [String] = []
            if fileCount > 0 {
                parts.append("\(fileCount) file")
            }
            if searchCount > 0 {
                parts.append("\(searchCount) \(searchCount == 1 ? "ricerca" : "ricerche")")
            }
            if parts.isEmpty {
                parts.append("\(group.events.count) operazioni")
            }
            return "Esplorazione effettuata (\(parts.joined(separator: ",")))"
        case .terminal:
            let commandCount = group.events.count
            return "Terminale in background (\(commandCount) \(commandCount == 1 ? "comando" : "comandi"))"
        case .edit:
            let fileCount = max(1, exploredTargets.count)
            return "Modifiche applicate (\(fileCount) file)"
        }
    }

    private var headerSymbolName: String {
        switch group.category {
        case .exploration:
            return "magnifyingglass.circle.fill"
        case .terminal:
            return "terminal.fill"
        case .edit:
            return "square.and.pencil"
        }
    }

    private var headerTint: Color {
        switch group.category {
        case .exploration:
            return DesignSystem.Colors.info
        case .terminal:
            return DesignSystem.Colors.warning
        case .edit:
            return DesignSystem.Colors.planColor
        }
    }

    private var exploredTargets: [String] {
        var values: [String] = []
        var seen: Set<String> = []
        for event in group.events {
            let raw = event.payload["path"]
                ?? event.payload["file"]
                ?? event.payload["query"]
                ?? event.payload["command"]
                ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let display = displayTarget(for: event, raw: trimmed)
            guard !display.isEmpty, !seen.contains(display) else { continue }
            seen.insert(display)
            values.append(display)
        }
        return values
    }

    private var searchEvents: [ToolTraceEvent] {
        group.events.filter {
            let type = $0.type.lowercased()
            let tool = MessageToolTraceToolIdentity.normalizedToolName(for: $0)
            return type.contains("search")
                || type.contains("grep")
                || type == "instant_grep"
                || ["grep", "search", "semantic_search", "codebase_search", "find_symbol", "find_references"].contains(tool)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    autoPresentationState.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: headerSymbolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(headerTint)

                    Text(summaryTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.75), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(group.events) { event in
                        ChatTurnInlineToolGroupRowView(
                            event: event,
                            messageIsStreaming: messageIsStreaming,
                            workspaceHints: workspaceHints,
                            onOpenFile: onOpenFile
                        )
                    }
                }
                .padding(.leading, 2)
            }
        }
        .onAppear(perform: syncAutoPresentationState)
        .onChange(of: lifecycleToken) { _ in
            syncAutoPresentationState()
        }
    }

    private func syncAutoPresentationState() {
        let next = InlineToolTraceGroupAutoPresentation.reconcile(
            current: autoPresentationState,
            hasRunningEvent: hasRunningEvent,
            hasEvents: hasEvents
        )
        guard next != autoPresentationState else { return }

        withAnimation(.easeOut(duration: 0.15)) {
            autoPresentationState = next
        }
    }

    private func displayTarget(for event: ToolTraceEvent, raw: String) -> String {
        if let change = ToolTraceFileChangeMapper.from(event: event) {
            return change.path ?? change.basename
        }
        if event.type == "bash" || event.type == "command_execution" {
            return String(raw.prefix(120))
        }
        if raw.contains("/") {
            return (raw as NSString).lastPathComponent
        }
        return raw
    }

    private static func hasEffectiveRunningEvent(
        events: [ToolTraceEvent],
        messageIsStreaming: Bool
    ) -> Bool {
        messageIsStreaming && events.contains(where: \.isRunning)
    }
}
