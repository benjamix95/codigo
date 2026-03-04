import SwiftUI

extension MessageToolTraceView {
    // MARK: - Tool Icon

    @ViewBuilder
    func toolIcon(for event: ToolTraceEvent) -> some View {
        let type = event.type.lowercased()
        let mcpTool = (event.payload["mcp_tool"] ?? "").lowercased()
        let tool = (
            type == "mcp_tool_call" && !mcpTool.isEmpty
                ? mcpTool
                : (event.payload["tool"] ?? event.payload["name"] ?? "")
        ).lowercased()

        if Self.isErrorType(event) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.error)
        } else if Self.isWarningType(event) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.warning)
        } else if type.contains("read") || type == "read_batch_started" || type == "read_batch_completed" || tool == "read" || tool == "read_range" {
            Image(systemName: "doc.text")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.info)
        } else if type.contains("grep") || type.contains("search") || type == "instant_grep" || tool == "grep" || tool == "codebase_search" || tool == "find_files" {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.ideColor)
        } else if type == "semantic_search" || tool == "semantic_search" {
            Image(systemName: "brain")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.ideColor)
        } else if type == "edit" || type == "file_change" || tool == "str_replace" || tool == "write" || tool == "edit" || tool == "create_file" || tool == "regex_replace" || tool == "parallel_apply" {
            Image(systemName: "pencil")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.success)
        } else if type == "bash" || type == "command_execution" || tool == "bash" {
            Image(systemName: "terminal")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.warning)
        } else if type.contains("web_search") || tool == "web_search" {
            Image(systemName: "globe")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.info)
        } else if type.contains("web_fetch") || tool == "web_fetch" {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.info)
        } else if type.contains("browser_action") || tool.hasPrefix("browser_") {
            let icon: String = {
                switch tool {
                case "browser_navigate": return "safari"
                case "browser_screenshot": return "camera.viewfinder"
                case "browser_console_logs": return "terminal"
                case "browser_click": return "cursorarrow.click.2"
                case "browser_type": return "keyboard"
                case "browser_evaluate_js": return "chevron.left.forwardslash.chevron.right"
                case "browser_get_content": return "doc.richtext"
                default: return "globe"
                }
            }()
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.browserColor)
        } else if type == "mcp_tool_call" || tool.hasPrefix("mcp") {
            let mcpIcon: String = {
                switch tool {
                case "mcp_batch": return "square.grid.3x3.topleft.filled"
                case "mcp_list_resources", "mcp_read_resource": return "tray.2"
                case "mcp_subscribe": return "bell.badge"
                case "mcp_list_prompts", "mcp_get_prompt": return "text.bubble"
                case "mcp_logs": return "list.bullet.rectangle"
                case "mcp_restart_server": return "arrow.clockwise.circle"
                case "mcp_health": return "heart.text.square"
                case "mcp_reconnect": return "arrow.triangle.2.circlepath"
                case "mcp_list_servers": return "server.rack"
                case "mcp_list_tools": return "wrench.and.screwdriver"
                case "mcp_describe_tool": return "doc.text.magnifyingglass"
                default: return "square.grid.3x3"
                }
            }()
            Image(systemName: mcpIcon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.mcpColor)
        } else if type == "skill_invocation" || tool == "skill" {
            Image(systemName: "sparkles")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.reviewColor)
        } else if type.contains("glob") || tool == "glob" || tool == "list_dir" {
            Image(systemName: "folder")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        } else if type == "read_lints" || tool == "diagnostics" {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.warning)
        } else if type.contains("debug") || tool.hasPrefix("debug_") {
            let debugIcon: String = {
                switch tool {
                case "debug_trace_analyze": return "waveform.path.ecg"
                case "debug_instrument": return "syringe"
                case "debug_timeline": return "chart.bar.xaxis"
                case "debug_snapshot": return "camera.circle"
                case "debug_test_check": return "checkmark.shield"
                case "debug_context": return "doc.text.magnifyingglass"
                case "debug_log": return "text.badge.plus"
                case "debug_query": return "magnifyingglass.circle"
                case "debug_hypothesize": return "lightbulb"
                case "debug_mark": return "pin.circle"
                case "debug_clean": return "trash.circle"
                case "debug_session": return "play.circle"
                case "debug_set_phase": return "arrow.right.circle"
                case "debug_resolve": return "checkmark.circle"
                default: return "ladybug"
                }
            }()
            Image(systemName: debugIcon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.debugColor)
        } else if tool == "git_diff" {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        } else {
            Image(systemName: "gearshape")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
        }
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
