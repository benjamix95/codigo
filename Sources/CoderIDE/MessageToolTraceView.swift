import SwiftUI

struct MessageToolTraceView: View {
    let events: [ToolTraceEvent]

    @State private var expandedIds: Set<UUID> = []
    @State private var isExpanded = false
    @State private var didAutoCompactAfterCompletion = false

    private let runningCompactLimit = 6

    private var orderedEvents: [ToolTraceEvent] {
        events
            .filter { ToolTraceVisibility.shouldDisplay(event: $0) }
            .sorted { lhs, rhs in
                if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
                return lhs.timestamp < rhs.timestamp
            }
    }

    private var hasRunningEvent: Bool {
        orderedEvents.contains(where: \.isRunning)
    }

    private var shouldShowRows: Bool {
        hasRunningEvent || isExpanded
    }

    private var displayEvents: [ToolTraceEvent] {
        if isExpanded {
            return orderedEvents
        }
        if hasRunningEvent {
            return Array(orderedEvents.suffix(runningCompactLimit))
        }
        return []
    }

    private var hiddenEventsCount: Int {
        max(0, orderedEvents.count - displayEvents.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
                .padding(.bottom, shouldShowRows ? 2 : 4)

            if shouldShowRows {
                ForEach(Array(displayEvents.enumerated()), id: \.element.id) { index, event in
                    traceRow(event, displayIndex: index + 1, compactMode: !isExpanded)
                }

                if hiddenEventsCount > 0 && !isExpanded {
                    Text("+\(hiddenEventsCount) previous operations")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .padding(.leading, 30)
                        .padding(.top, 2)
                }
            } else if !orderedEvents.isEmpty {
                Text(collapsedSummaryText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 22)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(maxWidth: 760, alignment: .leading)
        .onAppear {
            syncAutoPresentationState()
        }
        .onChange(of: events.count) { _, _ in
            syncAutoPresentationState()
        }
        .onChange(of: hasRunningEvent) { _, _ in
            syncAutoPresentationState()
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded.toggle()
                if !isExpanded {
                    expandedIds.removeAll()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("Tool operations")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("\(orderedEvents.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                if hasRunningEvent {
                    Text("running")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                } else if !orderedEvents.isEmpty {
                    Text("completed")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                if hasRunningEvent && hiddenEventsCount > 0 && !isExpanded {
                    Text("last \(displayEvents.count)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func traceRow(_ event: ToolTraceEvent, displayIndex: Int, compactMode: Bool) -> some View {
        let isRowExpanded = isExpanded && expandedIds.contains(event.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(displayIndex).")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(isRowExpanded ? 3 : 1)
                    if !compactMode, let detail = compactDetail(for: event) {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(isRowExpanded ? 4 : 1)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    if event.isRunning {
                        Text("RUN")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    if !compactMode {
                        Image(systemName: isRowExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !compactMode else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    if isRowExpanded {
                        expandedIds.remove(event.id)
                    } else {
                        expandedIds.insert(event.id)
                    }
                }
            }
            .padding(.vertical, compactMode ? 4 : 6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DesignSystem.Colors.divider.opacity(0.25))
                    .frame(height: 0.5)
            }

            if isRowExpanded {
                expandedDetails(for: event)
                    .padding(.leading, 30)
                    .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private func expandedDetails(for event: ToolTraceEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailField(label: "Type", value: event.type)
            detailField(label: "Kind", value: event.rawKind)
            if let groupId = event.groupId, !groupId.isEmpty {
                detailField(label: "Group", value: groupId)
            }
            if let command = event.payload["command"], !command.isEmpty {
                detailField(label: "Command", value: command)
            }
            if let query = event.payload["query"], !query.isEmpty {
                detailField(label: "Query", value: query)
            }
            if let path = event.payload["path"] ?? event.payload["file"], !path.isEmpty {
                detailField(label: "Path", value: path)
            }
            if let tool = event.payload["tool"], !tool.isEmpty {
                detailField(label: "Tool", value: tool)
            }
            if let server = event.payload["mcp_server"] ?? event.payload["server_id"], !server.isEmpty {
                detailField(label: "MCP server", value: server)
            }
            if let mcpTool = event.payload["mcp_tool"], !mcpTool.isEmpty {
                detailField(label: "MCP tool", value: mcpTool)
            }
            if let latency = event.payload["mcp_latency_ms"], !latency.isEmpty {
                detailField(label: "MCP latency", value: "\(latency) ms")
            }
            if let output = event.payload["output"], !output.isEmpty {
                detailField(label: "Output", value: output)
            }
            if let status = event.payload["status"], !status.isEmpty {
                detailField(label: "Status", value: status)
            }
        }
    }

    private func detailField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textSelection(.enabled)
                .lineLimit(8)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.55))
                )
        }
    }

    private func compactDetail(for event: ToolTraceEvent) -> String? {
        let candidates = [
            event.detail,
            event.payload["command"],
            event.payload["query"],
            event.payload["path"],
            event.payload["file"],
            event.payload["tool"],
            event.payload["mcp_tool"],
            event.payload["mcp_server"],
            event.payload["server_id"],
        ]
        for candidate in candidates {
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty, text != event.title {
                return String(text.prefix(180))
            }
        }
        return nil
    }

    private var collapsedSummaryText: String {
        let fileCount = inferredFileCount
        let searchCount = inferredSearchCount
        let commandCount = inferredCommandCount
        let editCount = inferredEditCount
        let mcpSummary = inferredMCPSummary
        let skillSummary = inferredSkillsSummary

        if fileCount > 0 && searchCount > 0 {
            var base = "Explored \(fileCount) \(pluralized("file", count: fileCount)), \(searchCount) \(pluralized("search", count: searchCount))"
            if let mcpSummary {
                base += " • \(mcpSummary)"
            }
            if let skillSummary {
                base += " • \(skillSummary)"
            }
            return base
        }

        var parts: [String] = []
        if fileCount > 0 {
            parts.append("\(fileCount) \(pluralized("file", count: fileCount)) explored")
        }
        if searchCount > 0 {
            parts.append("\(searchCount) \(pluralized("search", count: searchCount))")
        }
        if commandCount > 0 {
            parts.append("\(commandCount) \(pluralized("command", count: commandCount))")
        }
        if editCount > 0 {
            parts.append("\(editCount) \(pluralized("edit", count: editCount))")
        }
        if let mcpSummary {
            parts.append(mcpSummary)
        }
        if let skillSummary {
            parts.append(skillSummary)
        }
        if !parts.isEmpty {
            return parts.prefix(3).joined(separator: ", ")
        }
        return "\(orderedEvents.count) \(pluralized("operation", count: orderedEvents.count))"
    }

    private var inferredFileCount: Int {
        var paths = Set<String>()
        for event in orderedEvents {
            if let path = event.payload["path"], !path.isEmpty {
                paths.insert(path)
            }
            if let file = event.payload["file"], !file.isEmpty {
                paths.insert(file)
            }
            if let files = event.payload["files"], !files.isEmpty {
                let items = files
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                for item in items {
                    paths.insert(item)
                }
            }
        }
        return paths.count
    }

    private var inferredSearchCount: Int {
        orderedEvents.filter { event in
            let type = event.type.lowercased()
            return type.contains("search") || type.contains("grep")
        }.count
    }

    private var inferredCommandCount: Int {
        orderedEvents.filter { event in
            let type = event.type.lowercased()
            return type == "bash" || type == "command_execution"
        }.count
    }

    private var inferredEditCount: Int {
        orderedEvents.filter { event in
            let type = event.type.lowercased()
            return type == "edit" || type == "file_change"
        }.count
    }

    private var inferredMCPSummary: String? {
        let mcpEvents = orderedEvents.filter { ToolTraceVisibility.isMCPEvent(event: $0) }
        guard !mcpEvents.isEmpty else { return nil }

        var discoveredServers = Set<String>()
        var calledTools = Set<String>()

        for event in mcpEvents {
            let payload = event.payload
            let tool = (payload["tool"] ?? payload["name"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTool = tool.lowercased()
            let mcpTool = (payload["mcp_tool"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let server = (payload["mcp_server"] ?? payload["server_id"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedTool == "mcp_list_servers" {
                discoveredServers.formUnion(extractMCPServers(from: payload["output"] ?? ""))
            }
            if normalizedTool == "mcp_list_tools" {
                calledTools.formUnion(extractMCPTools(from: payload["output"] ?? ""))
            }

            if !mcpTool.isEmpty {
                calledTools.insert(mcpTool)
            } else if !tool.isEmpty, normalizedTool != "mcp_list_servers", normalizedTool != "mcp_list_tools",
                      normalizedTool != "mcp_describe_tool", normalizedTool != "mcp_health", normalizedTool != "mcp_reconnect" {
                calledTools.insert(tool)
            }
            if !server.isEmpty {
                discoveredServers.insert(server)
            }
        }

        var parts: [String] = []
        if !discoveredServers.isEmpty {
            parts.append("MCP \(discoveredServers.count) \(pluralized("server", count: discoveredServers.count))")
        }
        if !calledTools.isEmpty {
            parts.append("MCP \(calledTools.count) \(pluralized("tool", count: calledTools.count))")
        }
        if parts.isEmpty {
            return "MCP activity"
        }
        return parts.joined(separator: ", ")
    }

    private var inferredSkillsSummary: String? {
        let skills = inferredSkillNames
        guard !skills.isEmpty else { return nil }
        if skills.count <= 2 {
            return "Skills: \(skills.joined(separator: ", "))"
        }
        return "Skills: \(skills.prefix(2).joined(separator: ", ")) +\(skills.count - 2)"
    }

    private var inferredSkillNames: [String] {
        var names = Set<String>()
        for event in orderedEvents {
            for candidate in skillPathCandidates(for: event) {
                guard let name = extractSkillName(from: candidate) else { continue }
                names.insert(name)
            }
        }
        return names.sorted()
    }

    private func skillPathCandidates(for event: ToolTraceEvent) -> [String] {
        var candidates: [String] = []
        if let path = event.payload["path"] { candidates.append(path) }
        if let file = event.payload["file"] { candidates.append(file) }
        if let files = event.payload["files"] { candidates.append(contentsOf: files.components(separatedBy: ",")) }
        if let command = event.payload["command"] { candidates.append(command) }
        return candidates
    }

    private func extractSkillName(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let markers = ["/skills/", ".codex/skills/", ".agents/skills/"]
        guard markers.contains(where: { text.contains($0) }), text.lowercased().contains("skill.md") else {
            return nil
        }

        let normalized = text.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/").map(String.init)
        guard let skillsIndex = parts.firstIndex(of: "skills"), skillsIndex + 1 < parts.count else {
            return nil
        }
        let candidate = parts[skillsIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        return candidate
    }

    private func extractMCPServers(from output: String) -> Set<String> {
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var servers = Set<String>()
        for line in lines {
            if let firstToken = line.split(separator: " ").first {
                let token = String(firstToken).trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    servers.insert(token)
                }
            }
        }
        return servers
    }

    private func extractMCPTools(from output: String) -> Set<String> {
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var tools = Set<String>()
        for line in lines {
            let lhs = line.split(separator: ":").first.map(String.init) ?? line
            if let slash = lhs.firstIndex(of: "/") {
                let tool = lhs[lhs.index(after: slash)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !tool.isEmpty {
                    tools.insert(tool)
                }
            } else if !lhs.isEmpty {
                tools.insert(lhs)
            }
        }
        return tools
    }

    private func pluralized(_ noun: String, count: Int) -> String {
        count == 1 ? noun : "\(noun)s"
    }

    private func syncAutoPresentationState() {
        if hasRunningEvent {
            didAutoCompactAfterCompletion = false
            return
        }
        guard !orderedEvents.isEmpty else { return }
        guard !didAutoCompactAfterCompletion else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            isExpanded = false
            expandedIds.removeAll()
        }
        didAutoCompactAfterCompletion = true
    }
}
