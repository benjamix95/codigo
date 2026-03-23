import AppKit
import SwiftUI

struct ChatTurnView: View {
    let message: ChatMessage
    let context: ProjectContext?
    let modeColor: Color
    let isActuallyLoading: Bool
    let streamingStatusText: String
    let streamingDetailText: String?
    let traceEvents: [ToolTraceEvent]
    @ObservedObject var todoStore: TodoStore
    let conversationId: UUID
    let shouldShowTodo: Bool
    let onFileClicked: (String) -> Void
    let onReviewChanges: () -> Void
    let onReply: (() -> Void)?
    let onDelete: (() -> Void)?
    let showTopDivider: Bool

    @State private var didCopyMessage = false

    private var blocks: [PersistedChatTimelineBlock] { message.resolvedTimelineBlocks }
    private var visibleBlocks: [PersistedChatTimelineBlock] {
        blocks.filter { block in
            block.kind != .toolTrace
                && block.kind != .commands
                && block.kind != .files
                && block.kind != .status
        }
    }
    private var linearOperationEvents: [ToolTraceEvent] {
        traceEvents
            .filter(shouldShowInLinearChatOperationFeed)
            .sorted { lhs, rhs in
                if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
                return lhs.timestamp < rhs.timestamp
            }
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
            if !linearOperationEvents.isEmpty {
                linearOperationFeed
            }
            if let primary = visibleBlocks.first(where: { $0.kind == .primaryText }) {
                if !primary.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownContentView(
                        content: primary.text,
                        context: context,
                        onFileClicked: onFileClicked,
                        textAlignment: .leading,
                        isStreaming: message.isStreaming && isActuallyLoading
                    )
                    .frame(maxWidth: 800, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            ForEach(visibleBlocks.filter { $0.kind != .primaryText }) { block in
                ArtifactCardView(
                    block: block,
                    accentColor: modeColor,
                    context: context,
                    onFileClicked: onFileClicked
                )
            }
            if message.isStreaming && isActuallyLoading {
                streamingFooter
            }
            actions
        }
        .frame(maxWidth: 860, alignment: .leading)
    }

    private var linearOperationFeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(linearOperationEvents.enumerated()), id: \.element.id) { _, event in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: linearOperationIcon(for: event))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(linearOperationColor(for: event))
                        .frame(width: 14, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(linearOperationTitle(for: event))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = linearOperationDetail(for: event), !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: 800, alignment: .leading)
    }

    private func shouldShowInLinearChatOperationFeed(_ event: ToolTraceEvent) -> Bool {
        let type = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["policy_ack", "usage", "reasoning", "turn_started", "turn_completed"].contains(type) {
            return false
        }
        if type == "agent" || type == "subagent_text" || type == "subagent_batch_done" {
            return true
        }
        return ToolTraceVisibility.shouldDisplay(event: event)
    }

    private func linearOperationTitle(for event: ToolTraceEvent) -> String {
        let type = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawTool = (event.payload["mcp_tool"] ?? event.payload["tool"] ?? event.payload["name"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tool = rawTool
            .replacingOccurrences(of: "coderide_", with: "")
            .replacingOccurrences(of: "mcp_", with: "")
        let filePath = event.payload["path"] ?? event.payload["file"] ?? event.payload["target_path"] ?? ""
        let basename = filePath.isEmpty ? "" : (filePath as NSString).lastPathComponent
        let query = (event.payload["query"] ?? event.payload["pattern"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch type {
        case "todo_write":
            return "Todo aggiornato"
        case "todo_read":
            return "Leggo la todo list"
        case "plan_create":
            return "Piano creato"
        case "plan_step_upsert", "plan_step_batch_update", "plan_step_reorder", "plan_step_dependency_set":
            return "Piano aggiornato"
        case "plan_set_walkthrough":
            return "Riepilogo del piano aggiornato"
        case "plan_request_user_input":
            return "Servono chiarimenti"
        case "command_execution", "bash":
            return "Eseguo un comando"
        case "agent":
            return "Avvio lavoro in parallelo"
        case "subagent_text":
            return event.payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (event.payload["title"] ?? "Aggiornamento parallelo")
                : "Aggiornamento parallelo"
        case "mcp_tool_call":
            switch tool {
            case "read", "read_range":
                return basename.isEmpty ? "Leggo un file" : "Leggo \(basename)"
            case "grep", "search", "codebase_search", "semantic_search":
                return query.isEmpty ? "Cerco nel progetto" : "Cerco: \(query)"
            case "write", "edit", "str_replace", "create_file", "delete_file", "parallel_apply", "regex_replace":
                return basename.isEmpty ? "Modifico file" : "Modifico \(basename)"
            case "todo_write":
                return "Todo aggiornato"
            case "plan_create":
                return "Piano creato"
            case "plan_step_upsert", "plan_step_batch_update", "plan_step_reorder", "plan_step_dependency_set":
                return "Piano aggiornato"
            case "subagent_explorer", "subagent_coder", "subagent_debugger", "subagent_reviewer",
                 "subagent_bughunter", "subagent_testwriter", "subagent_docwriter", "subagent_securityauditor":
                return "Avvio lavoro in parallelo"
            default:
                return event.isRunning ? "Operazione in corso" : "Operazione completata"
            }
        default:
            if !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return sanitizedLinearOperationText(event.title)
            }
            return event.isRunning ? "Operazione in corso" : "Operazione completata"
        }
    }

    private func linearOperationDetail(for event: ToolTraceEvent) -> String? {
        let type = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type == "todo_write" || type == "plan_create" || type.hasPrefix("plan_step_") {
            let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return detail.isEmpty ? nil : sanitizedLinearOperationText(detail)
        }
        if type == "command_execution" || type == "bash" {
            let command = event.payload["command"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return command.isEmpty ? nil : command
        }
        let path = (event.payload["path"] ?? event.payload["file"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            return path
        }
        let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return detail.isEmpty ? nil : sanitizedLinearOperationText(detail)
    }

    private func linearOperationIcon(for event: ToolTraceEvent) -> String {
        let type = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch type {
        case "todo_write", "todo_read":
            return "checklist"
        case "plan_create", "plan_step_upsert", "plan_step_batch_update", "plan_step_reorder",
             "plan_step_dependency_set", "plan_set_walkthrough", "plan_request_user_input":
            return "list.bullet.rectangle"
        case "command_execution", "bash":
            return "terminal"
        case "agent", "subagent_text", "subagent_batch_done":
            return "square.grid.2x2"
        case "tool_validation_error", "tool_execution_error", "tool_timeout", "permission_denied", "error":
            return "exclamationmark.triangle.fill"
        default:
            return "circle.fill"
        }
    }

    private func linearOperationColor(for event: ToolTraceEvent) -> Color {
        let type = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch type {
        case "plan_create", "plan_step_upsert", "plan_step_batch_update", "plan_step_reorder",
             "plan_step_dependency_set", "plan_set_walkthrough", "plan_request_user_input":
            return DesignSystem.Colors.planColor
        case "todo_write", "todo_read":
            return .secondary
        case "tool_validation_error", "tool_execution_error", "tool_timeout", "permission_denied", "error":
            return DesignSystem.Colors.error
        default:
            return .secondary
        }
    }

    private func sanitizedLinearOperationText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "MCP call • ", with: "")
            .replacingOccurrences(of: "coderide/", with: "")
            .replacingOccurrences(of: "coderide_", with: "")
            .replacingOccurrences(of: "mcp_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
}
