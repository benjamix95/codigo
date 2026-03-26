import SwiftUI

extension MessageToolTraceView {
    // MARK: - Tool Icon

    @ViewBuilder
    func toolIcon(for event: ToolTraceEvent) -> some View {
        WorkspaceCatalogToolIcon(event: event)
    }

    // MARK: - Tool Title

    @ViewBuilder
    func toolTitle(for event: ToolTraceEvent) -> some View {
        let path = event.payload["path"] ?? event.payload["file"] ?? ""
        let basename = path.isEmpty ? "" : (path as NSString).lastPathComponent

        if !basename.isEmpty && ToolTraceFileChangeMapper.isFileChangeEvent(event) {
            Button {
                if let resolved = FileChangePreviewResolver.resolveOpenPath(
                    for: ToolTraceFileChangeMapper.from(event: event)!,
                    workspaceHints: workspaceHints
                ) {
                    onOpenFile(resolved)
                }
            } label: {
                Text(event.title)
                    .underline(pattern: .solid, color: .clear)
            }
            .buttonStyle(.plain)
        } else {
            Text(event.title)
        }
    }
}

struct MessageToolTraceToolIdentity {
    let symbolName: String
    let tint: Color

    static func resolve(for event: ToolTraceEvent) -> MessageToolTraceToolIdentity {
        let type = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tool = normalizedToolName(for: event)

        if MessageToolTraceView.isErrorType(event) {
            return .init(symbolName: "xmark.circle", tint: DesignSystem.Colors.error)
        }
        if MessageToolTraceView.isWarningType(event) {
            return .init(symbolName: "exclamationmark.triangle", tint: DesignSystem.Colors.warning)
        }
        if let exactIdentity = exactToolIdentity(for: tool) {
            return exactIdentity
        }
        if type.contains("browser_action") || tool.hasPrefix("browser_") {
            let symbolName: String = switch tool {
            case "browser_navigate": "safari"
            case "browser_screenshot": "camera.viewfinder"
            case "browser_console_logs": "terminal"
            case "browser_click": "cursorarrow.click.2"
            case "browser_type": "keyboard"
            case "browser_evaluate_js": "chevron.left.forwardslash.chevron.right"
            case "browser_get_content": "doc.richtext"
            default: "globe"
            }
            return .init(symbolName: symbolName, tint: DesignSystem.Colors.browserColor)
        }
        if type == "mcp_tool_call" || tool.hasPrefix("mcp_") {
            let symbolName: String = switch tool {
            case "mcp_batch": "square.grid.3x3.topleft.filled"
            case "mcp_list_resources", "mcp_read_resource": "tray.2"
            case "mcp_subscribe": "bell.badge"
            case "mcp_list_prompts", "mcp_get_prompt": "text.bubble"
            case "mcp_logs": "list.bullet.rectangle"
            case "mcp_restart_server": "arrow.clockwise.circle"
            case "mcp_health": "heart.text.square"
            case "mcp_reconnect": "arrow.triangle.2.circlepath"
            case "mcp_list_servers": "server.rack"
            case "mcp_list_tools": "wrench.and.screwdriver"
            case "mcp_describe_tool": "doc.text.magnifyingglass"
            default: "square.grid.3x3"
            }
            return .init(symbolName: symbolName, tint: DesignSystem.Colors.mcpColor)
        }
        if type == "skill_invocation" || tool == "skill" {
            return .init(symbolName: "sparkles", tint: DesignSystem.Colors.reviewColor)
        }
        if type == "read_lints" || tool == "diagnostics" {
            return .init(symbolName: "exclamationmark.triangle", tint: DesignSystem.Colors.warning)
        }
        if type.contains("debug") || tool.hasPrefix("debug_") {
            let symbolName: String = switch tool {
            case "debug_trace_analyze": "waveform.path.ecg"
            case "debug_instrument": "syringe"
            case "debug_timeline": "chart.bar.xaxis"
            case "debug_snapshot": "camera.circle"
            case "debug_test_check": "checkmark.shield"
            case "debug_context": "doc.text.magnifyingglass"
            case "debug_log": "text.badge.plus"
            case "debug_query": "magnifyingglass.circle"
            case "debug_hypothesize": "lightbulb"
            case "debug_mark": "pin.circle"
            case "debug_clean": "trash.circle"
            case "debug_session": "play.circle"
            case "debug_set_phase": "arrow.right.circle"
            case "debug_resolve": "checkmark.circle"
            default: "ladybug"
            }
            return .init(symbolName: symbolName, tint: DesignSystem.Colors.debugColor)
        }
        if tool == "git_diff" {
            return .init(symbolName: "arrow.triangle.branch", tint: DesignSystem.Colors.textSecondary)
        }
        if type == "semantic_search" {
            return .init(symbolName: "brain", tint: DesignSystem.Colors.ideColor)
        }
        if type.contains("read") || type == "read_batch_started" || type == "read_batch_completed" {
            return .init(symbolName: "doc.text", tint: DesignSystem.Colors.info)
        }
        if type.contains("grep") || type.contains("search") || type == "instant_grep" {
            return .init(symbolName: "magnifyingglass", tint: DesignSystem.Colors.ideColor)
        }
        if type == "edit" || type == "file_change" {
            return .init(symbolName: "square.and.pencil", tint: DesignSystem.Colors.success)
        }
        if type == "bash" || type == "command_execution" {
            return .init(symbolName: "terminal", tint: DesignSystem.Colors.warning)
        }
        if type.contains("web_search") {
            return .init(symbolName: "globe", tint: DesignSystem.Colors.info)
        }
        if type.contains("web_fetch") {
            return .init(symbolName: "arrow.down.doc", tint: DesignSystem.Colors.info)
        }
        return .init(symbolName: "gearshape", tint: DesignSystem.Colors.textQuaternary)
    }

    static func normalizedToolName(for event: ToolTraceEvent) -> String {
        let type = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mcpTool = cleaned(event.payload["mcp_tool"] ?? event.payload["mcpTool"] ?? "")
        if type == "mcp_tool_call", !mcpTool.isEmpty {
            return mcpTool
        }
        return cleaned(event.payload["tool"] ?? event.payload["name"] ?? "")
    }

    private static func exactToolIdentity(for tool: String) -> MessageToolTraceToolIdentity? {
        switch tool {
        case "semantic_search":
            return .init(symbolName: "brain", tint: DesignSystem.Colors.ideColor)
        case "codebase_search":
            return .init(symbolName: "square.text.square", tint: DesignSystem.Colors.ideColor)
        case "find_symbol":
            return .init(symbolName: "text.magnifyingglass", tint: DesignSystem.Colors.ideColor)
        case "find_references":
            return .init(symbolName: "arrow.triangle.branch", tint: DesignSystem.Colors.ideColor)
        case "grep", "search", "search_symbols":
            return .init(symbolName: "magnifyingglass", tint: DesignSystem.Colors.ideColor)
        case "find_files", "glob", "list_dir":
            return .init(symbolName: "folder", tint: DesignSystem.Colors.textTertiary)
        case "read":
            return .init(symbolName: "doc.text", tint: DesignSystem.Colors.info)
        case "read_range", "batch_read":
            return .init(symbolName: "doc.text.magnifyingglass", tint: DesignSystem.Colors.info)
        case "write", "edit":
            return .init(symbolName: "square.and.pencil", tint: DesignSystem.Colors.success)
        case "str_replace":
            return .init(symbolName: "text.cursor", tint: DesignSystem.Colors.success)
        case "regex_replace":
            return .init(symbolName: "character.cursor.ibeam", tint: DesignSystem.Colors.success)
        case "create_file":
            return .init(symbolName: "doc.badge.plus", tint: DesignSystem.Colors.success)
        case "delete_file":
            return .init(symbolName: "trash", tint: DesignSystem.Colors.success)
        case "parallel_apply":
            return .init(symbolName: "square.grid.2x2", tint: DesignSystem.Colors.success)
        case "bash":
            return .init(symbolName: "terminal", tint: DesignSystem.Colors.warning)
        case "web_search":
            return .init(symbolName: "globe", tint: DesignSystem.Colors.info)
        case "web_fetch":
            return .init(symbolName: "arrow.down.doc", tint: DesignSystem.Colors.info)
        case "skill":
            return .init(symbolName: "sparkles", tint: DesignSystem.Colors.reviewColor)
        default:
            return nil
        }
    }

    private static func cleaned(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        let parts = trimmed
            .split(whereSeparator: { ch in
                ch == "." || ch == ":" || ch == "/" || ch == "\\"
            })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let last = parts.last else { return trimmed }
        return last.replacingOccurrences(of: "coderide_", with: "")
    }
}
