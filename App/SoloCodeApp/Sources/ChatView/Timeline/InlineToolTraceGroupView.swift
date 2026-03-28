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
                    Text(summaryTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(group.events) { event in
                        InlineToolTraceGroupRow(
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

struct InlineToolTraceGroupRow: View {
    let event: ToolTraceEvent
    var messageIsStreaming: Bool = true
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void

    private var showsRunningChrome: Bool {
        event.isRunning && messageIsStreaming
    }

    private var title: String {
        let tool = MessageToolTraceToolIdentity.normalizedToolName(for: event)
        let target = displayTarget

        if event.type == "bash" || event.type == "command_execution" {
            return target
        }
        switch tool {
        case "read", "read_range", "batch_read":
            return "Read \(target)"
        case "list_dir", "glob", "find_files", "file_outline":
            return "List \(target)"
        case "grep", "search", "semantic_search", "codebase_search", "find_symbol", "find_references":
            return "Search \(target)"
        case "edit", "write", "str_replace", "regex_replace", "create_file", "delete_file":
            return "Edit \(target)"
        default:
            if !target.isEmpty, target != event.title {
                return "\(event.title) \(target)"
            }
            return event.title
        }
    }

    private var displayTarget: String {
        let raw = event.payload["path"]
            ?? event.payload["file"]
            ?? event.payload["query"]
            ?? event.payload["command"]
            ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let change = ToolTraceFileChangeMapper.from(event: event) {
            return change.path ?? change.basename
        }
        if event.type == "bash" || event.type == "command_execution" {
            return String(trimmed.prefix(120))
        }
        if trimmed.contains("/") {
            return (trimmed as NSString).lastPathComponent
        }
        return trimmed
    }

    private var openPath: String? {
        if let change = ToolTraceFileChangeMapper.from(event: event) {
            return FileChangePreviewResolver.resolveOpenPath(
                for: change,
                workspaceHints: workspaceHints
            )
        }
        let candidate = event.payload["path"] ?? event.payload["file"] ?? ""
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        HStack(spacing: 8) {
            if let openPath {
                Button {
                    onOpenFile(openPath)
                } label: {
                    Text(title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsRunningChrome {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
            } else if MessageToolTraceView.isErrorType(event) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.error)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.success.opacity(0.8))
            }
        }
    }
}
