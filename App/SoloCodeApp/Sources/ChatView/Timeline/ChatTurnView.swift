import AppKit
import SwiftUI

enum ChatTurnTimelineOrdering {
    static func visibleBlocks(
        from blocks: [PersistedChatTimelineBlock]
    ) -> [PersistedChatTimelineBlock] {
        blocks.filter { block in
            block.kind != .toolTrace
                && block.kind != .commands
                && block.kind != .files
                && block.kind != .status
        }
    }

    static func narrativeBlocks(
        from visibleBlocks: [PersistedChatTimelineBlock]
    ) -> [PersistedChatTimelineBlock] {
        visibleBlocks.filter { $0.kind == .reasoning }
    }

    static func detailBlocks(
        from visibleBlocks: [PersistedChatTimelineBlock]
    ) -> [PersistedChatTimelineBlock] {
        visibleBlocks.filter { $0.kind != .primaryText && $0.kind != .reasoning }
    }
}

enum ChatTurnTimelineInterleaver {
    static func segments(
        blocks: [PersistedChatTimelineBlock],
        traceEvents: [ToolTraceEvent],
        liveSubagentCards: [SwarmLiveCardState] = [],
        subagentSnapshots: [SubagentCardSnapshot] = []
    ) -> [ChatTurnInterleavedSegment] {
        var segments: [ChatTurnInterleavedSegment] = []

        for block in blocks {
            switch block.kind {
            case .primaryText:
                let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                segments.append(.text(id: block.id, content: block.text, sequence: block.sequence))
            case .reasoning:
                segments.append(.reasoning(id: block.id, text: block.text, sequence: block.sequence))
            case .toolMarker:
                // Placeholder only. Individual tool events are injected directly
                // from their own sequence numbers so the chat reads linearly.
                continue
            default:
                segments.append(.artifact(id: block.id, block: block, sequence: block.sequence))
            }
        }

        let collapsedTraceEvents = ToolTraceEventCollapser.collapseSupersededToolStates(traceEvents)
        for event in collapsedTraceEvents {
            segments.append(
                .toolEvent(
                    id: event.id.uuidString.lowercased(),
                    event: event,
                    sequence: event.sequence
                )
            )
        }

        let baseSequence = max(
            blocks.map(\.sequence).max() ?? 0,
            traceEvents.map(\.sequence).max() ?? 0
        )

        for (index, card) in liveSubagentCards.enumerated() {
            segments.append(
                .subagentLiveCard(
                    id: card.swarmId.lowercased(),
                    card: card,
                    sequence: sequenceForSubagentCard(
                        swarmId: card.swarmId,
                        traceEvents: traceEvents,
                        fallbackBase: baseSequence,
                        offset: index
                    )
                )
            )
        }

        for (index, snapshot) in subagentSnapshots.enumerated() {
            segments.append(
                .subagentSnapshot(
                    id: snapshot.swarmId.lowercased(),
                    snapshot: snapshot,
                    sequence: sequenceForSubagentCard(
                        swarmId: snapshot.swarmId,
                        traceEvents: traceEvents,
                        fallbackBase: baseSequence + liveSubagentCards.count,
                        offset: index
                    )
                )
            )
        }

        return segments.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.id < rhs.id
        }
        .collapsedConsecutiveToolEvents()
    }

    private static func sequenceForSubagentCard(
        swarmId: String,
        traceEvents: [ToolTraceEvent],
        fallbackBase: Int,
        offset: Int
    ) -> Int {
        let normalizedSwarmId = swarmId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let earliestMatch = traceEvents
            .filter({
                ($0.payload["swarm_id"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == normalizedSwarmId
            })
            .map(\.sequence)
            .min() {
            return earliestMatch
        }
        return fallbackBase + offset + 1
    }
}

private extension Array where Element == ChatTurnInterleavedSegment {
    func collapsedConsecutiveToolEvents() -> [ChatTurnInterleavedSegment] {
        var result: [ChatTurnInterleavedSegment] = []
        var index = 0

        while index < count {
            guard case .toolEvent(_, let event, _) = self[index],
                  let category = ChatTurnView.toolGroupCategory(for: event) else {
                result.append(self[index])
                index += 1
                continue
            }

            var groupedEvents: [ToolTraceEvent] = [event]
            var lookahead = index + 1
            while lookahead < count {
                guard case .toolEvent(_, let nextEvent, _) = self[lookahead],
                      ChatTurnView.toolGroupCategory(for: nextEvent) == category else {
                    break
                }
                groupedEvents.append(nextEvent)
                lookahead += 1
            }

            if groupedEvents.count > 1 {
                let firstEvent = groupedEvents[0]
                let group = ChatTurnToolEventGroup(
                    id: "\(category.rawValue)-\(firstEvent.id.uuidString.lowercased())",
                    category: category,
                    events: groupedEvents,
                    sequence: firstEvent.sequence
                )
                result.append(.toolGroup(id: group.id, group: group, sequence: group.sequence))
            } else {
                result.append(self[index])
            }
            index = lookahead
        }

        return result
    }
}

struct ChatTurnView: View {
    let message: ChatMessage
    let context: ProjectContext?
    let modeColor: Color
    let isActuallyLoading: Bool
    let streamingStatusText: String
    let streamingDetailText: String?
    let traceEvents: [ToolTraceEvent]
    let inlineActivities: [TaskActivity]
    let supervisorActivities: [TaskActivity]
    let liveSubagentCards: [SwarmLiveCardState]
    @ObservedObject var todoStore: TodoStore
    let conversationId: UUID
    let shouldShowTodo: Bool
    let onFileClicked: (String) -> Void
    let onReviewChanges: () -> Void
    let onOpenSubagentPanel: (String) -> Void
    let onStopSubagent: () -> Void
    let onReply: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let showTopDivider: Bool

    @State private var didCopyMessage = false

    private var blocks: [PersistedChatTimelineBlock] { message.resolvedTimelineBlocks }
    private var visibleBlocks: [PersistedChatTimelineBlock] {
        ChatTurnTimelineOrdering.visibleBlocks(from: blocks)
    }
    private var narrativeBlocks: [PersistedChatTimelineBlock] {
        ChatTurnTimelineOrdering.narrativeBlocks(from: visibleBlocks)
    }
    private var detailBlocks: [PersistedChatTimelineBlock] {
        ChatTurnTimelineOrdering.detailBlocks(from: visibleBlocks)
    }
    private var todoItems: [TodoItem] {
        todoStore.displayTodosForChat(for: conversationId)
    }
    private var inlineTraceEvents: [ToolTraceEvent] {
        traceEvents
            .filter { shouldShowInLinearChatOperationFeed($0, showTodoCard: shouldShowTodo && !todoItems.isEmpty) }
            .sorted { lhs, rhs in
                if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
                return lhs.timestamp < rhs.timestamp
            }
    }
    private var traceWorkspaceHints: [String] {
        context?.folderPaths.filter { !$0.isEmpty } ?? []
    }

    // MARK: - Interleaved Timeline Segments

    /// Builds an interleaved timeline: text, reasoning, tool ops, artifacts
    /// sorted chronologically by sequence number.
    private var interleavedSegments: [ChatTurnInterleavedSegment] {
        ChatTurnTimelineInterleaver.segments(
            blocks: visibleBlocks,
            traceEvents: inlineTraceEvents,
            liveSubagentCards: liveSubagentCards,
            subagentSnapshots: message.subagentCards ?? []
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showTopDivider {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.bottom, 20)
            }
            header
            // Interleaved timeline: text, reasoning, tool ops in chronological order
            ForEach(interleavedSegments) { segment in
                switch segment {
                case .text(_, let content, _):
                    MarkdownContentView(
                        content: content,
                        context: context,
                        onFileClicked: onFileClicked,
                        textAlignment: .leading,
                        isStreaming: message.isStreaming && isActuallyLoading
                    )
                    .frame(maxWidth: 800, alignment: .leading)
                    .padding(.vertical, 4)

                case .reasoning(let id, let text, _):
                    ThinkingBlocksView(
                        blocks: [ReasoningBlock(id: id, text: text)],
                        isLiveStreaming: message.isStreaming && isActuallyLoading
                    )
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.vertical, 4)

                case .toolEvent(_, let event, _):
                    InlineToolTraceEventView(
                        event: event,
                        workspaceHints: traceWorkspaceHints,
                        onOpenFile: onFileClicked
                    )
                    .frame(maxWidth: 800, alignment: .leading)

                case .toolGroup(_, let group, _):
                    InlineToolTraceGroupView(
                        group: group,
                        workspaceHints: traceWorkspaceHints,
                        onOpenFile: onFileClicked
                    )
                    .frame(maxWidth: 800, alignment: .leading)

                case .subagentLiveCard(_, let card, _):
                    SubagentChatCardView(
                        card: card,
                        onOpenInPanel: { onOpenSubagentPanel(card.swarmId) },
                        onStop: onStopSubagent
                    )
                    .padding(.horizontal, 2)

                case .subagentSnapshot(_, let snapshot, _):
                    SubagentSnapshotCardView(snapshot: snapshot)
                        .padding(.horizontal, 2)

                case .artifact(_, let block, _):
                    ArtifactCardView(
                        block: block,
                        accentColor: modeColor,
                        context: context,
                        onFileClicked: onFileClicked
                    )
                }
            }
            if message.isStreaming && isActuallyLoading {
                streamingFooter
            }
            actions
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private func shouldShowInLinearChatOperationFeed(_ event: ToolTraceEvent, showTodoCard: Bool) -> Bool {
        shouldShowOperationEventInLinearChat(
            eventType: event.type,
            payload: event.payload,
            showTodoCard: showTodoCard
        )
    }

    private var header: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(modeColor.opacity(0.6))
                .frame(width: 5.5, height: 5.5)
            Spacer(minLength: 0)
        }
    }

    private var streamingFooter: some View {
        HStack(spacing: 6) {
            Text(streamingStatusText.isEmpty ? "Thinking" : streamingStatusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textShimmer(active: true)
            if let streamingDetailText, !streamingDetailText.isEmpty {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(streamingDetailText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textShimmer(active: true)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.exportMarkdownContent, forType: .string)
                didCopyMessage = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    didCopyMessage = false
                }
            } label: {
                Image(systemName: didCopyMessage ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.plain)

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
            }

            if let onReply {
                Button(action: onReply) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
            }

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func toolGroupCategory(for event: ToolTraceEvent) -> ChatTurnToolEventGroupCategory? {
        let type = event.type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let tool = MessageToolTraceToolIdentity.normalizedToolName(for: event)

        if type == "bash" || type == "command_execution" || tool == "bash" {
            return .terminal
        }
        if ToolTraceFileChangeMapper.isFileChangeEvent(event)
            || ["edit", "write", "str_replace", "regex_replace", "create_file", "delete_file"].contains(tool) {
            return .edit
        }
        if type.contains("read")
            || type.contains("search")
            || type.contains("grep")
            || type == "instant_grep"
            || ["read", "read_range", "batch_read", "glob", "list_dir", "find_files", "grep", "search", "semantic_search", "codebase_search", "find_symbol", "find_references", "file_outline"].contains(tool) {
            return .exploration
        }
        return nil
    }
}

private struct InlineToolTraceEventView: View {
    let event: ToolTraceEvent
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void

    private var identity: MessageToolTraceToolIdentity {
        MessageToolTraceToolIdentity.resolve(for: event)
    }

    private var compactDetail: String? {
        let fileChange = ToolTraceFileChangeMapper.from(event: event)
        if let fileChange {
            let added = max(0, fileChange.added)
            let removed = max(0, fileChange.removed)
            if added > 0 || removed > 0 {
                return "+\(added) -\(removed)"
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
        if let change = ToolTraceFileChangeMapper.from(event: event) {
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
            Image(systemName: identity.symbolName)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(identity.tint)
                .frame(width: 14, alignment: .center)

            if let openPath {
                Button {
                    onOpenFile(openPath)
                } label: {
                    Text(event.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .textShimmer(active: event.isRunning)
                }
                .buttonStyle(.plain)
            } else {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .textShimmer(active: event.isRunning)
            }

            if let compactDetail, !compactDetail.isEmpty {
                Text(compactDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if event.isRunning {
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

private struct InlineToolTraceGroupView: View {
    let group: ChatTurnToolEventGroup
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void

    @State private var isExpanded = true

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
                    isExpanded.toggle()
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
                            workspaceHints: workspaceHints,
                            onOpenFile: onOpenFile
                        )
                    }
                }
                .padding(.leading, 2)
            }
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
}

private struct InlineToolTraceGroupRow: View {
    let event: ToolTraceEvent
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void

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
            if event.isRunning {
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
