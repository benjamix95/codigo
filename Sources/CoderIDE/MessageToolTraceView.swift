import SwiftUI

struct MessageToolTraceView: View {
    let events: [ToolTraceEvent]
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void
    var onInteractionStart: (() -> Void)? = nil

    @State private var expandedIds: Set<UUID> = []
    @State private var isExpanded = false
    @State private var didAutoCompactAfterCompletion = false
    @State private var userDidManuallyExpand = false
    @State private var expandedFileIds: Set<UUID> = []
    @State private var filePreviewByEventId: [UUID: FileChangePreviewResult] = [:]
    @State private var loadingPreviewIds: Set<UUID> = []
    @State private var isCompactDiffExpanded = false
    @State private var isCompactDiffLoading = false
    @State private var isHoveringHeader = false

    private let runningCompactLimit = 8

    private struct DerivedState {
        let orderedEvents: [ToolTraceEvent]
        let hasRunningEvent: Bool
        let shouldShowRows: Bool
        let displayEvents: [ToolTraceEvent]
        let hiddenEventsCount: Int
        let fileChanges: [ToolTraceFileChange]
        let fileAddedTotal: Int
        let fileRemovedTotal: Int
        let genericDisplayEvents: [ToolTraceEvent]
        let totalDurationMs: Int
        let errorCount: Int
        let warningCount: Int
        let collapsedSummary: String

        init(events: [ToolTraceEvent], isExpanded: Bool, runningCompactLimit: Int, collapser: ([ToolTraceEvent]) -> [ToolTraceEvent]) {
            let filtered = events
                .filter { ToolTraceVisibility.shouldDisplay(event: $0) }
                .sorted { lhs, rhs in
                    if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
                    return lhs.timestamp < rhs.timestamp
                }
            let ordered = collapser(filtered)
            self.orderedEvents = ordered
            self.hasRunningEvent = ordered.contains(where: \.isRunning)
            self.shouldShowRows = !ordered.isEmpty || isExpanded

            if isExpanded {
                displayEvents = ordered
            } else {
                displayEvents = Array(ordered.suffix(runningCompactLimit))
            }
            hiddenEventsCount = max(0, ordered.count - displayEvents.count)
            fileChanges = ToolTraceFileChangeMapper.collect(from: ordered)
            fileAddedTotal = fileChanges.reduce(0) { $0 + max(0, $1.added) }
            fileRemovedTotal = fileChanges.reduce(0) { $0 + max(0, $1.removed) }
            if isExpanded, !fileChanges.isEmpty {
                genericDisplayEvents = displayEvents.filter { !ToolTraceFileChangeMapper.isFileChangeEvent($0) }
            } else {
                genericDisplayEvents = displayEvents
            }
            totalDurationMs = ordered.compactMap { Int($0.payload["duration_ms"] ?? "") }.reduce(0, +)
            errorCount = ordered.filter { Self.isErrorEvent($0) }.count
            warningCount = ordered.filter { Self.isWarningEvent($0) }.count
            collapsedSummary = Self.computeCollapsedSummary(orderedEvents: ordered)
        }

        private static func computeCollapsedSummary(orderedEvents: [ToolTraceEvent]) -> String {
            var filePaths = Set<String>()
            var readCount = 0
            var searchCount = 0
            var commandCount = 0
            var editCount = 0
            var mcpCount = 0
            var mcpBatchCount = 0
            var mcpResourceCount = 0
            var mcpPromptCount = 0
            var browserCount = 0
            var skillNames = Set<String>()

            for event in orderedEvents {
                if let path = event.payload["path"], !path.isEmpty { filePaths.insert(path) }
                if let file = event.payload["file"], !file.isEmpty { filePaths.insert(file) }
                let type = event.type.lowercased()
                if type == "read_batch_completed" || (event.payload["source"] ?? "") == "synthetic_command_read" { readCount += 1 }
                if type.contains("search") || type.contains("grep") || type == "instant_grep" { searchCount += 1 }
                if type == "bash" || type == "command_execution" { commandCount += 1 }
                if ToolTraceFileChangeMapper.isFileChangeEvent(event) { editCount += 1 }
                if ToolTraceVisibility.isMCPEvent(event: event) {
                    mcpCount += 1
                    let mcpTool = (event.payload["tool"] ?? event.payload["mcp_tool"] ?? "").lowercased()
                    if mcpTool == "mcp_batch" { mcpBatchCount += 1 }
                    if mcpTool == "mcp_list_resources" || mcpTool == "mcp_read_resource" { mcpResourceCount += 1 }
                    if mcpTool == "mcp_list_prompts" || mcpTool == "mcp_get_prompt" { mcpPromptCount += 1 }
                }
                if type.contains("browser_action") || (event.payload["tool"] ?? "").hasPrefix("browser_") { browserCount += 1 }
                if event.type == "skill_invocation" || event.payload["tool"] == "skill",
                   let skill = event.payload["skill"], !skill.isEmpty { skillNames.insert(skill) }
                for raw in skillPathCandidates(for: event) {
                    if let name = extractSkillName(from: raw) { skillNames.insert(name) }
                }
            }

            let fileCount = filePaths.count
            func pluralized(_ noun: String, count: Int, plural: String? = nil) -> String {
                count == 1 ? noun : (plural ?? "\(noun)s")
            }
            var parts: [String] = []
            if editCount > 0 { parts.append("\(editCount) \(pluralized("edit", count: editCount))") }
            if readCount > 0 || fileCount > 0 {
                parts.append("\(max(fileCount, readCount)) \(pluralized("file", count: max(fileCount, readCount))) read")
            }
            if searchCount > 0 { parts.append("\(searchCount) \(pluralized("search", count: searchCount, plural: "searches"))") }
            if commandCount > 0 { parts.append("\(commandCount) \(pluralized("command", count: commandCount))") }
            if mcpCount > 0 {
                var mcpDetail = "MCP \(mcpCount) \(pluralized("call", count: mcpCount))"
                var extras: [String] = []
                if mcpBatchCount > 0 { extras.append("\(mcpBatchCount) batch") }
                if mcpResourceCount > 0 { extras.append("\(mcpResourceCount) \(pluralized("resource", count: mcpResourceCount))") }
                if mcpPromptCount > 0 { extras.append("\(mcpPromptCount) \(pluralized("prompt", count: mcpPromptCount))") }
                if !extras.isEmpty { mcpDetail += " (\(extras.joined(separator: ", ")))" }
                parts.append(mcpDetail)
            }
            if browserCount > 0 { parts.append("\(browserCount) browser \(pluralized("action", count: browserCount))") }
            if !skillNames.isEmpty {
                let skills = skillNames.sorted()
                parts.append(skills.count <= 2 ? "Skills: \(skills.joined(separator: ", "))" : "Skills: \(skills.prefix(2).joined(separator: ", ")) +\(skills.count - 2)")
            }
            if !parts.isEmpty { return parts.prefix(3).joined(separator: " \u{00B7} ") }
            return "\(orderedEvents.count) \(pluralized("operation", count: orderedEvents.count))"
        }

        private static func skillPathCandidates(for event: ToolTraceEvent) -> [String] {
            var candidates: [String] = []
            if let skill = event.payload["skill"], !skill.isEmpty {
                candidates.append(".codex/skills/\(skill)/SKILL.md")
            }
            if let path = event.payload["path"] { candidates.append(path) }
            if let file = event.payload["file"] { candidates.append(file) }
            if let files = event.payload["files"] { candidates.append(contentsOf: files.components(separatedBy: ",")) }
            if let command = event.payload["command"] { candidates.append(command) }
            return candidates
        }

        private static func extractSkillName(from raw: String) -> String? {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let markers = ["/skills/", ".codex/skills/", ".agents/skills/"]
            guard markers.contains(where: { text.contains($0) }), text.lowercased().contains("skill.md") else { return nil }
            let normalized = text.replacingOccurrences(of: "\\", with: "/")
            let parts = normalized.split(separator: "/").map(String.init)
            guard let skillsIndex = parts.firstIndex(of: "skills"), skillsIndex + 1 < parts.count else { return nil }
            let candidate = parts[skillsIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { return nil }
            return candidate
        }

        private static func isErrorEvent(_ event: ToolTraceEvent) -> Bool {
            let type = event.type.lowercased()
            let status = (event.payload["status"] ?? "").lowercased()
            if MessageToolTraceView.hardErrorTypes.contains(type) || type.contains("error") {
                return true
            }
            // Non-zero exits often surface as "failed" status for command-like tools.
            // Keep them out of global error badges unless explicitly marked as error.
            return status == "error" || status == "fatal"
        }

        private static func isWarningEvent(_ event: ToolTraceEvent) -> Bool {
            guard !isErrorEvent(event) else { return false }
            let type = event.type.lowercased()
            let status = (event.payload["status"] ?? "").lowercased()
            let severity = (event.payload["severity"] ?? "").lowercased()
            if status == "failed" || status == "warning" {
                return true
            }
            if severity == "warning" {
                return true
            }
            // Non-critical failed-type events should render as warnings.
            return type.contains("failed")
        }
    }

    private static let hardErrorTypes: Set<String> = [
        "error",
        "permission_denied",
        "tool_execution_error",
        "tool_timeout",
        "tool_validation_error",
        "web_fetch_failed",
        "web_search_failed",
    ]

    private final class DerivedCache {
        var state: DerivedState?
        var eventCount: Int = -1
        var isExpanded: Bool = false
        var runningHash: Int = -1
        var eventSignature: Int = -1
    }
    @State private var derivedCache = DerivedCache()

    private struct EventsChangeToken: Equatable {
        let count: Int
        let lastId: UUID?
        let lastSequence: Int
        let lastRunning: Bool
        let lastStatus: String
        let lastDetail: String
    }

    private var eventsChangeToken: EventsChangeToken {
        let last = events.last
        return EventsChangeToken(
            count: events.count,
            lastId: last?.id,
            lastSequence: last?.sequence ?? -1,
            lastRunning: last?.isRunning ?? false,
            lastStatus: last?.payload["status"] ?? "",
            lastDetail: last?.detail ?? ""
        )
    }

    private static func eventsSignature(_ events: [ToolTraceEvent]) -> Int {
        events.reduce(into: 17) { hash, event in
            hash = (hash &* 31) &+ event.id.hashValue
            hash = (hash &* 31) &+ event.type.hashValue
            hash = (hash &* 31) &+ (event.isRunning ? 1 : 0)
            hash = (hash &* 31) &+ (event.payload["status"] ?? "").hashValue
            hash = (hash &* 31) &+ (event.detail ?? "").hashValue
        }
    }

    private func currentDerived() -> DerivedState {
        let runningHash = events.reduce(0) { h, e in h ^ (e.isRunning ? e.id.hashValue : 0) }
        let signature = Self.eventsSignature(events)
        if let cached = derivedCache.state,
           events.count == derivedCache.eventCount,
           isExpanded == derivedCache.isExpanded,
           runningHash == derivedCache.runningHash,
           signature == derivedCache.eventSignature {
            return cached
        }
        let d = DerivedState(
            events: events,
            isExpanded: isExpanded,
            runningCompactLimit: runningCompactLimit,
            collapser: collapseSupersededToolStates
        )
        derivedCache.state = d
        derivedCache.eventCount = events.count
        derivedCache.isExpanded = isExpanded
        derivedCache.runningHash = runningHash
        derivedCache.eventSignature = signature
        return d
    }

    var body: some View {
        let derived = currentDerived()
        VStack(alignment: .leading, spacing: 0) {
            headerView(derived: derived)

            if derived.shouldShowRows {
                VStack(alignment: .leading, spacing: 0) {
                    if derived.hiddenEventsCount > 0 && !isExpanded {
                        hiddenEventsButton(count: derived.hiddenEventsCount)
                    }

                    ForEach(Array(derived.genericDisplayEvents.enumerated()), id: \.element.id) { index, event in
                        traceRow(event, displayIndex: index + 1 + derived.hiddenEventsCount, compactMode: !isExpanded, derived: derived)
                    }

                    if isExpanded, !derived.fileChanges.isEmpty {
                        fileChangesSectionView(derived: derived)
                            .padding(.top, 4)
                    }

                    if isExpanded, derived.hasRunningEvent {
                        collapseShortcutRow
                            .padding(.top, 6)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: 760, alignment: .leading)
        .onAppear {
            syncAutoPresentationState(derived: currentDerived())
        }
        .onChange(of: eventsChangeToken) { _, _ in
            syncAutoPresentationState(derived: currentDerived())
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded else { return }
            let changes = currentDerived().fileChanges
            loadCompactDiffPreviewIfNeeded(changes: changes)
            for change in changes {
                loadPreviewIfNeeded(for: change)
            }
        }
    }

    // MARK: - Header

    private func headerView(derived: DerivedState) -> some View {
        Button {
            onInteractionStart?()
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded.toggle()
                if isExpanded { userDidManuallyExpand = true }
                if !isExpanded {
                    userDidManuallyExpand = false
                    expandedIds.removeAll()
                    expandedFileIds.removeAll()
                    isCompactDiffExpanded = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .frame(width: 12)

                if derived.hasRunningEvent {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                } else if derived.errorCount > 0 {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.error)
                } else if derived.warningCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.warning)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.success.opacity(0.7))
                }

                Text(headerTitle(derived: derived))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Spacer(minLength: 0)

                if derived.fileAddedTotal > 0 || derived.fileRemovedTotal > 0 {
                    HStack(spacing: 3) {
                        Text("+\(derived.fileAddedTotal)")
                            .foregroundStyle(DesignSystem.Colors.success)
                        Text("-\(derived.fileRemovedTotal)")
                            .foregroundStyle(DesignSystem.Colors.error)
                    }
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                }

                if derived.totalDurationMs > 0 && !derived.hasRunningEvent {
                    Text(formatDuration(derived.totalDurationMs))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringHeader = $0 }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isHoveringHeader ? DesignSystem.Colors.backgroundSecondary.opacity(0.5) : Color.clear)
        )
    }

    private var collapseShortcutRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.and.line.horizontal.and.arrow.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
            Button("Collapse trace") {
                onInteractionStart?()
                withAnimation(.easeOut(duration: 0.12)) {
                    isExpanded = false
                    userDidManuallyExpand = false
                    expandedIds.removeAll()
                    expandedFileIds.removeAll()
                    isCompactDiffExpanded = false
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }

    private func headerTitle(derived: DerivedState) -> String {
        let count = derived.orderedEvents.count
        if derived.hasRunningEvent {
            return "\(count) \(pluralized("operation", count: count)) running..."
        }
        if !derived.orderedEvents.isEmpty {
            return derived.collapsedSummary
        }
        return "Tool operations"
    }

    // MARK: - Hidden Events

    private func hiddenEventsButton(count: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)
                Text("\(count) more \(pluralized("operation", count: count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trace Row

    @ViewBuilder
    private func traceRow(_ event: ToolTraceEvent, displayIndex: Int, compactMode: Bool, derived: DerivedState) -> some View {
        let isRowExpanded = isExpanded && expandedIds.contains(event.id)
        let isError = Self.isErrorType(event)
        let isWarning = Self.isWarningType(event)
        let durationMs = Int(event.payload["duration_ms"] ?? "") ?? 0

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                toolIcon(for: event)
                    .frame(width: 14, alignment: .center)

                toolTitle(for: event)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        isError
                            ? DesignSystem.Colors.error
                            : (isWarning ? DesignSystem.Colors.warning : .primary)
                    )
                    .lineLimit(1)
                    .textShimmer(active: event.isRunning)

                if let detail = compactDetail(for: event), !compactMode || detail.count < 60 {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                        .textShimmer(active: event.isRunning)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    if let counters = editLineCounters(for: event) {
                        Text("+\(counters.added)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.success)
                        Text("-\(counters.removed)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.error)
                    }

                    if event.isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else if durationMs > 0 {
                        Text(formatDuration(durationMs))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    }

                    if !compactMode {
                        Image(systemName: isRowExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !compactMode else {
                    withAnimation(.easeOut(duration: 0.15)) { isExpanded = true }
                    return
                }
                withAnimation(.easeInOut(duration: 0.12)) {
                    if isRowExpanded {
                        expandedIds.remove(event.id)
                    } else {
                        expandedIds.insert(event.id)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        isError
                            ? DesignSystem.Colors.error.opacity(0.06)
                            : (isWarning ? DesignSystem.Colors.warning.opacity(0.06) : Color.clear)
                    )
            )

            if isRowExpanded {
                expandedDetails(for: event)
                    .padding(.leading, 20)
                    .padding(.trailing, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.3))
                    )
            }
        }
    }

    // MARK: - Tool Icon

    @ViewBuilder
    private func toolIcon(for event: ToolTraceEvent) -> some View {
        let type = event.type.lowercased()
        let tool = (event.payload["tool"] ?? event.payload["name"] ?? "").lowercased()

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
    private func toolTitle(for event: ToolTraceEvent) -> some View {
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

    // MARK: - File Changes Section

    private func fileChangesSectionView(derived: DerivedState) -> some View {
        let compactDiff = compactDiffPreview(fileChanges: derived.fileChanges)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("\(derived.fileChanges.count) \(pluralized("file", count: derived.fileChanges.count)) changed")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("+\(derived.fileAddedTotal)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(derived.fileRemovedTotal)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.error)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)

            ForEach(derived.fileChanges) { change in
                fileChangeRow(change)
            }

            if let compactDiff {
                compactDiffSection(diff: compactDiff, derived: derived)
            } else if !derived.fileChanges.isEmpty {
                buildDiffButton()
            }
        }
    }

    @ViewBuilder
    private func fileChangeRow(_ change: ToolTraceFileChange) -> some View {
        let isExpandedRow = expandedFileIds.contains(change.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: change.kind == .created ? "plus.circle" : change.kind == .deleted ? "minus.circle" : "pencil.circle")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(change.kind == .created ? DesignSystem.Colors.success : change.kind == .deleted ? DesignSystem.Colors.error : DesignSystem.Colors.info)

                Button {
                    openFileForChange(change)
                } label: {
                    Text(change.basename)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                if let path = change.path, !path.isEmpty {
                    Text(shortenedPath(path))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("+\(max(0, change.added))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(max(0, change.removed))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.error)

                Button {
                    toggleExpandedFile(change)
                } label: {
                    Image(systemName: isExpandedRow ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)

            if isExpandedRow {
                if loadingPreviewIds.contains(change.id) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Loading diff...")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                } else if let preview = filePreviewByEventId[change.id] {
                    if case .diff = preview {
                        diffBlock(preview.text)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    } else {
                        codeBlock(label: preview.label, value: preview.text)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.25))
        )
    }

    @ViewBuilder
    private func compactDiffSection(diff: String, derived: DerivedState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isCompactDiffExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text("Unified diff")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: isCompactDiffExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCompactDiffExpanded {
                diffBlock(diff)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.25))
        )
    }

    @ViewBuilder
    private func buildDiffButton() -> some View {
        if !isCompactDiffLoading {
            Button {
                loadCompactDiffPreviewIfNeeded()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text("Build unified diff")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Building diff...")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Expanded Details

    @ViewBuilder
    private func expandedDetails(for event: ToolTraceEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let command = event.payload["command"], !command.isEmpty {
                codeBlock(label: "Command", value: command)
            }
            if let query = event.payload["query"], !query.isEmpty {
                detailPill(label: "Query", value: query)
            }
            if let path = event.payload["path"] ?? event.payload["file"], !path.isEmpty {
                HStack(spacing: 4) {
                    Text("Path")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Button {
                        onOpenFile(path)
                    } label: {
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.info)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let tool = event.payload["tool"], !tool.isEmpty {
                detailPill(label: "Tool", value: tool)
            }
            if let server = event.payload["mcp_server"] ?? event.payload["server_id"], !server.isEmpty {
                detailPill(label: "MCP Server", value: server)
            }
            if let mcpTool = event.payload["mcp_tool"], !mcpTool.isEmpty {
                detailPill(label: "MCP Tool", value: mcpTool)
            }
            if let latency = event.payload["mcp_latency_ms"], !latency.isEmpty {
                detailPill(label: "Latency", value: "\(latency)ms")
            }
            if let uri = event.payload["uri"], !uri.isEmpty {
                detailPill(label: "URI", value: uri)
            }
            if let promptName = event.payload["prompt_name"], !promptName.isEmpty {
                detailPill(label: "Prompt", value: promptName)
            }
            if let output = event.payload["output"], !output.isEmpty {
                if output.hasPrefix("data:image/png;base64,") {
                    browserScreenshotBlock(base64: String(output.dropFirst("data:image/png;base64,".count)))
                } else {
                    codeBlock(label: "Output", value: String(output.prefix(4000)))
                }
            }
            if let diffPreview = nonEmpty(
                event.payload["diffPreview"]
                    ?? event.payload["diff"]
                    ?? event.payload["patch"]
                    ?? event.payload["unified_diff"]
                    ?? event.payload["changes_preview"]
            ) {
                diffBlock(diffPreview)
            }
            if let status = event.payload["status"], !status.isEmpty, status.lowercased() != "completed" {
                detailPill(label: "Status", value: status)
            }
            if let notes = event.payload["notes"], !notes.isEmpty {
                detailPill(label: "Notes", value: notes)
            }
        }
    }

    // MARK: - UI Components

    @ViewBuilder
    private func browserScreenshotBlock(base64: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.browserColor)
                Text("Browser Screenshot")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            if let data = Data(base64Encoded: base64),
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 480, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            } else {
                Text("(screenshot data unavailable)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
    }

    private func detailPill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private func codeBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
                )
        }
    }

    @ViewBuilder
    private func diffBlock(_ diff: String) -> some View {
        Text(buildDiffAttributed(diff))
            .font(.system(size: 10, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
            )
    }

    // MARK: - Diff Rendering

    private func buildDiffAttributed(_ diff: String) -> AttributedString {
        let maxLines = 250
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        var result = AttributedString()
        for (i, line) in lines.prefix(maxLines).enumerated() {
            if i > 0 { result += AttributedString("\n") }
            var attr = AttributedString(String(line))
            attr.foregroundColor = nsDiffLineColor(String(line))
            result += attr
        }
        if lines.count > maxLines {
            var truncation = AttributedString("\n... \(lines.count - maxLines) more lines")
            truncation.foregroundColor = NSColor(DesignSystem.Colors.textTertiary)
            result += truncation
        }
        return result
    }

    private func nsDiffLineColor(_ line: String) -> NSColor {
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return NSColor(DesignSystem.Colors.textTertiary)
        }
        if line.hasPrefix("@@") {
            return NSColor(DesignSystem.Colors.info.opacity(0.7))
        }
        if line.hasPrefix("+") {
            return NSColor(DesignSystem.Colors.success)
        }
        if line.hasPrefix("-") {
            return NSColor(DesignSystem.Colors.error)
        }
        return NSColor(DesignSystem.Colors.textSecondary)
    }

    // MARK: - Helpers

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        }
        let seconds = Double(ms) / 1000.0
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return "\(minutes)m \(remainingSeconds)s"
    }

    private func shortenedPath(_ path: String) -> String {
        let components = path.split(separator: "/").map(String.init)
        if components.count <= 2 { return path }
        let last2 = components.suffix(2).joined(separator: "/")
        return ".../" + last2
    }

    private static func isErrorType(_ event: ToolTraceEvent) -> Bool {
        let type = event.type.lowercased()
        let status = (event.payload["status"] ?? "").lowercased()
        if Self.hardErrorTypes.contains(type) || type.contains("error") {
            return true
        }
        return status == "error" || status == "fatal"
    }

    private static func isWarningType(_ event: ToolTraceEvent) -> Bool {
        guard !isErrorType(event) else { return false }
        let type = event.type.lowercased()
        let status = (event.payload["status"] ?? "").lowercased()
        let severity = (event.payload["severity"] ?? "").lowercased()
        if status == "failed" || status == "warning" {
            return true
        }
        if severity == "warning" {
            return true
        }
        return type.contains("failed")
    }

    private func compactDetail(for event: ToolTraceEvent) -> String? {
        if let lineSummary = editLineSummary(for: event) {
            return lineSummary
        }
        let type = event.type.lowercased()
        let isSearchLike = type.contains("grep") || type.contains("search") || type == "instant_grep"
        let candidates: [String?]
        if isSearchLike {
            candidates = [
                event.payload["query"],
                event.payload["command"],
                event.detail,
                event.payload["path"],
                event.payload["file"],
            ]
        } else {
            candidates = [
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
        }
        for candidate in candidates {
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty, text != event.title {
                return String(text.prefix(120))
            }
        }
        return nil
    }

    private func compactDiffPreview(fileChanges: [ToolTraceFileChange]) -> String? {
        var sections: [String] = []
        for change in fileChanges {
            guard let chunk = compactDiffChunk(for: change) else { continue }
            let path = nonEmpty(change.path) ?? change.basename
            sections.append("### \(change.kind.displayTitle) \(path)\n\(chunk)")
        }
        guard !sections.isEmpty else { return nil }
        return truncatePreview(sections.joined(separator: "\n\n"), limit: 24_000)
    }

    private func compactDiffChunk(for change: ToolTraceFileChange) -> String? {
        if let payloadPreview = nonEmpty(change.diffPreview) {
            return payloadPreview
        }
        if let cached = filePreviewByEventId[change.id],
           case .diff(let text) = cached,
           let nonEmptyText = nonEmpty(text) {
            return nonEmptyText
        }
        return nil
    }

    private func editLineSummary(for event: ToolTraceEvent) -> String? {
        guard let counters = editLineCounters(for: event) else { return nil }
        return "+\(counters.added) -\(counters.removed)"
    }

    private func editLineCounters(for event: ToolTraceEvent) -> (added: Int, removed: Int)? {
        let payload = event.payload
        let hasFileHints = ToolTraceFileChangeMapper.isFileChangeEvent(event)
            || nonEmpty(payload["path"]) != nil
            || nonEmpty(payload["file"]) != nil
            || nonEmpty(payload["diffPreview"]) != nil
            || nonEmpty(payload["diff"]) != nil
        guard hasFileHints else { return nil }

        let explicitAdded = parseInt(payload: payload, keys: [
            "linesAdded", "additions", "insertions", "added",
        ]) ?? 0
        let explicitRemoved = parseInt(payload: payload, keys: [
            "linesRemoved", "deletions", "removed",
        ]) ?? 0

        if explicitAdded > 0 || explicitRemoved > 0 {
            return (explicitAdded, explicitRemoved)
        }

        if let diff = nonEmpty(
            payload["diffPreview"]
                ?? payload["diff"]
                ?? payload["patch"]
                ?? payload["unified_diff"]
                ?? payload["changes_preview"]
        ) {
            return diffLineCounts(from: diff)
        }

        if let summary = nonEmpty(
            payload["detail"]
                ?? payload["output"]
                ?? payload["result"]
                ?? payload["stdout"]
        ),
            let summaryCounters = replacementSummaryLineCounts(from: summary) {
            return summaryCounters
        }

        if ToolTraceFileChangeMapper.isFileChangeEvent(event) {
            return (0, 0)
        }
        return nil
    }

    private func diffLineCounts(from diff: String) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") {
                continue
            }
            if line.hasPrefix("+") {
                added += 1
            } else if line.hasPrefix("-") {
                removed += 1
            }
        }
        return (max(0, added), max(0, removed))
    }

    private func parseInt(payload: [String: String], keys: [String]) -> Int? {
        for key in keys {
            let raw = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            if let value = Int(raw) {
                return value
            }
        }
        return nil
    }

    private static let replacementSummaryRegex = try! NSRegularExpression(
        pattern: "\\((\\d+)\\s+lines?\\s*(?:->|\u{2192})\\s*(\\d+)\\s+lines?\\)",
        options: [.caseInsensitive]
    )

    private func replacementSummaryLineCounts(from summary: String) -> (added: Int, removed: Int)? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = Self.replacementSummaryRegex.firstMatch(in: trimmed, options: [], range: range),
              let oldRange = Range(match.range(at: 1), in: trimmed),
              let newRange = Range(match.range(at: 2), in: trimmed),
              let oldLines = Int(trimmed[oldRange]),
              let newLines = Int(trimmed[newRange]) else {
            return nil
        }
        return (added: max(0, newLines), removed: max(0, oldLines))
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func truncatePreview(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end])
            + "\n\n... diff truncated (\(text.count - limit) characters hidden)"
    }

    private func pluralized(_ noun: String, count: Int, plural: String? = nil) -> String {
        count == 1 ? noun : (plural ?? "\(noun)s")
    }

    private func collapseSupersededToolStates(_ input: [ToolTraceEvent]) -> [ToolTraceEvent] {
        ToolTraceEventCollapser.collapseSupersededToolStates(input)
    }

    private func toggleExpandedFile(_ change: ToolTraceFileChange) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if expandedFileIds.contains(change.id) {
                expandedFileIds.remove(change.id)
                return
            }
            expandedFileIds.insert(change.id)
        }
        loadPreviewIfNeeded(for: change)
    }

    private func openFileForChange(_ change: ToolTraceFileChange) {
        guard let path = FileChangePreviewResolver.resolveOpenPath(
            for: change,
            workspaceHints: workspaceHints
        ) else {
            return
        }
        onOpenFile(path)
    }

    private func loadPreviewIfNeeded(for change: ToolTraceFileChange) {
        if filePreviewByEventId[change.id] != nil || loadingPreviewIds.contains(change.id) {
            return
        }
        loadingPreviewIds.insert(change.id)
        Task {
            let result = await FileChangePreviewResolver.shared.resolvePreview(
                for: change,
                workspaceHints: workspaceHints
            )
            await MainActor.run {
                filePreviewByEventId[change.id] = result
                loadingPreviewIds.remove(change.id)
            }
        }
    }

    private func loadCompactDiffPreviewIfNeeded(changes initialChanges: [ToolTraceFileChange]? = nil) {
        guard !isCompactDiffLoading else { return }
        let changes = initialChanges ?? currentDerived().fileChanges
        guard !changes.isEmpty else { return }
        isCompactDiffLoading = true

        Task {
            for change in changes {
                if compactDiffChunk(for: change) != nil {
                    continue
                }
                let result = await FileChangePreviewResolver.shared.resolvePreview(
                    for: change,
                    workspaceHints: workspaceHints
                )
                await MainActor.run {
                    filePreviewByEventId[change.id] = result
                }
            }

            await MainActor.run {
                isCompactDiffLoading = false
                let updatedChanges = currentDerived().fileChanges
                if isExpanded, compactDiffPreview(fileChanges: updatedChanges) != nil {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isCompactDiffExpanded = true
                    }
                }
            }
        }
    }

    private func syncAutoPresentationState(derived: DerivedState) {
        let ordered = derived.orderedEvents
        let running = ordered.contains(where: \.isRunning)
        if running {
            didAutoCompactAfterCompletion = false
            return
        }
        guard !ordered.isEmpty else { return }
        guard !didAutoCompactAfterCompletion else { return }
        guard !userDidManuallyExpand else {
            didAutoCompactAfterCompletion = true
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            isExpanded = false
            expandedIds.removeAll()
            expandedFileIds.removeAll()
            isCompactDiffExpanded = false
        }
        isCompactDiffLoading = false
        didAutoCompactAfterCompletion = true
    }

}
