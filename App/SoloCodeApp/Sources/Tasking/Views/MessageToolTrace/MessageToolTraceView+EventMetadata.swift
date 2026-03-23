import SwiftUI

extension MessageToolTraceView {
    // MARK: - Tool Icon

    @ViewBuilder
    func toolIcon(for event: ToolTraceEvent) -> some View {
        let identity = MessageToolTraceToolIdentity.resolve(for: event)

        Image(systemName: identity.symbolName)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(identity.tint)
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
        if type.contains("read") || type == "read_batch_started" || type == "read_batch_completed"
            || tool == "read" || tool == "read_range"
        {
            return .init(symbolName: "doc.text", tint: DesignSystem.Colors.info)
        }
        if type == "semantic_search" || tool == "semantic_search" {
            return .init(symbolName: "brain", tint: DesignSystem.Colors.ideColor)
        }
        if type.contains("grep") || type.contains("search") || type == "instant_grep"
            || tool == "grep" || tool == "search" || tool == "codebase_search"
            || tool == "find_symbol" || tool == "find_references"
        {
            return .init(symbolName: "magnifyingglass", tint: DesignSystem.Colors.ideColor)
        }
        if type == "edit" || type == "file_change"
            || tool == "str_replace" || tool == "write" || tool == "edit"
            || tool == "create_file" || tool == "delete_file" || tool == "regex_replace"
            || tool == "parallel_apply"
        {
            return .init(symbolName: "pencil", tint: DesignSystem.Colors.success)
        }
        if type == "bash" || type == "command_execution" || tool == "bash" {
            return .init(symbolName: "terminal", tint: DesignSystem.Colors.warning)
        }
        if type.contains("web_search") || tool == "web_search" {
            return .init(symbolName: "globe", tint: DesignSystem.Colors.info)
        }
        if type.contains("web_fetch") || tool == "web_fetch" {
            return .init(symbolName: "arrow.down.doc", tint: DesignSystem.Colors.info)
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
        if type.contains("glob") || tool == "glob" || tool == "list_dir" || tool == "find_files" {
            return .init(symbolName: "folder", tint: DesignSystem.Colors.textTertiary)
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

    private static func cleaned(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "functions.", with: "")
            .replacingOccurrences(of: "coderide_", with: "")
    }
}
