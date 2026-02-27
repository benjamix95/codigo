import SwiftUI

struct MessageToolTraceView: View {
    let events: [ToolTraceEvent]
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void

    @State private var expandedIds: Set<UUID> = []
    @State private var isExpanded = false
    @State private var didAutoCompactAfterCompletion = false
    @State private var expandedFileIds: Set<UUID> = []
    @State private var filePreviewByEventId: [UUID: FileChangePreviewResult] = [:]
    @State private var loadingPreviewIds: Set<UUID> = []
    @State private var isCompactDiffExpanded = false
    @State private var isCompactDiffLoading = false

    private let runningCompactLimit = 6

    /// Precomputed derived state from `events` + `isExpanded`.
    /// Avoids recomputing orderedEvents 5-10x per render cycle.
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
            self.shouldShowRows = hasRunningEvent || isExpanded

            if isExpanded {
                displayEvents = ordered
            } else if hasRunningEvent {
                displayEvents = Array(ordered.suffix(runningCompactLimit))
            } else {
                displayEvents = []
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
        }
    }

    /// Cached derived state – recomputed only when events count or isExpanded changes.
    @State private var cachedDerived: DerivedState?
    @State private var lastDerivedEventCount: Int = -1
    @State private var lastDerivedIsExpanded: Bool = false

    private func currentDerived() -> DerivedState {
        if let cached = cachedDerived,
           events.count == lastDerivedEventCount,
           isExpanded == lastDerivedIsExpanded {
            return cached
        }
        return DerivedState(
            events: events,
            isExpanded: isExpanded,
            runningCompactLimit: runningCompactLimit,
            collapser: collapseSupersededToolStates
        )
    }

    private func refreshDerived() {
        let d = DerivedState(
            events: events,
            isExpanded: isExpanded,
            runningCompactLimit: runningCompactLimit,
            collapser: collapseSupersededToolStates
        )
        cachedDerived = d
        lastDerivedEventCount = events.count
        lastDerivedIsExpanded = isExpanded
    }

    var body: some View {
        let derived = currentDerived()
        VStack(alignment: .leading, spacing: 2) {
            headerView(derived: derived)
                .padding(.bottom, derived.shouldShowRows ? 2 : 4)

            if derived.shouldShowRows {
                if isExpanded, !derived.fileChanges.isEmpty {
                    fileChangesSectionView(derived: derived)
                        .padding(.leading, 22)
                        .padding(.trailing, 4)
                        .padding(.bottom, 4)
                }

                ForEach(Array(derived.genericDisplayEvents.enumerated()), id: \.element.id) { index, event in
                    traceRow(event, displayIndex: index + 1, compactMode: !isExpanded)
                }

                if derived.hiddenEventsCount > 0 && !isExpanded {
                    Text("+\(derived.hiddenEventsCount) previous operations")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .padding(.leading, 30)
                        .padding(.top, 2)
                }
            } else if !derived.orderedEvents.isEmpty {
                Text(collapsedSummaryText(derived: derived))
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
            refreshDerived()
            syncAutoPresentationState()
        }
        .onChange(of: events.count) { _, _ in
            refreshDerived()
            syncAutoPresentationState()
        }
        .onChange(of: isExpanded) { _, expanded in
            refreshDerived()
            guard expanded else { return }
            let changes = (cachedDerived ?? currentDerived()).fileChanges
            loadCompactDiffPreviewIfNeeded()
            for change in changes {
                loadPreviewIfNeeded(for: change)
            }
        }
    }

    private func headerView(derived: DerivedState) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded.toggle()
                if !isExpanded {
                    expandedIds.removeAll()
                    expandedFileIds.removeAll()
                    isCompactDiffExpanded = false
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
                Text("\(derived.orderedEvents.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                if derived.hasRunningEvent {
                    Text("running")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                } else if !derived.orderedEvents.isEmpty {
                    Text("completed")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                if derived.hasRunningEvent && derived.hiddenEventsCount > 0 && !isExpanded {
                    Text("last \(derived.displayEvents.count)")
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

    private func fileChangesSectionView(derived: DerivedState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("Files changed \(derived.fileChanges.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("+\(derived.fileAddedTotal)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(derived.fileRemovedTotal)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.error)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)

            if let compactDiff = compactDiffPreview(fileChanges: derived.fileChanges) {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCompactDiffExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                            Text("Compact diff")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            Text("+\(derived.fileAddedTotal)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.success)
                            Text("-\(derived.fileRemovedTotal)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.error)
                            Spacer(minLength: 0)
                            Image(systemName: isCompactDiffExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isCompactDiffExpanded {
                        diffField(label: "Diff", value: compactDiff)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.divider.opacity(0.2), lineWidth: 0.5)
                )
            } else if !derived.fileChanges.isEmpty {
                HStack(spacing: 8) {
                    if isCompactDiffLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    Button {
                        loadCompactDiffPreviewIfNeeded()
                    } label: {
                        Text(isCompactDiffLoading ? "Building compact diff..." : "Build compact diff")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCompactDiffLoading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.divider.opacity(0.2), lineWidth: 0.5)
                )
            }

            ForEach(derived.fileChanges) { change in
                fileChangeRow(change)
            }
        }
    }

    @ViewBuilder
    private func fileChangeRow(_ change: ToolTraceFileChange) -> some View {
        let isExpandedRow = expandedFileIds.contains(change.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    openFileForChange(change)
                } label: {
                    Text("\(change.kind.displayTitle) \(change.basename)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                if change.diffSource.isDerived {
                    Text("derived")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.45))
                        )
                }

                Spacer(minLength: 0)

                Text("+\(max(0, change.added))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(max(0, change.removed))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.error)

                Button {
                    toggleExpandedFile(change)
                } label: {
                    Image(systemName: isExpandedRow ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
                .buttonStyle(.plain)
            }

            if let path = change.path, !path.isEmpty {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
            }

            if isExpandedRow {
                if loadingPreviewIds.contains(change.id) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading preview...")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.vertical, 2)
                } else if let preview = filePreviewByEventId[change.id] {
                    if case .diff = preview {
                        diffField(label: preview.label, value: preview.text)
                    } else {
                        detailField(label: preview.label, value: preview.text)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignSystem.Colors.divider.opacity(0.2), lineWidth: 0.5)
        )
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
                    if let counters = editLineCounters(for: event) {
                        Text("+\(counters.added)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.success)
                        Text("-\(counters.removed)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.error)
                    }
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
            if let lineSummary = editLineSummary(for: event) {
                detailField(label: "Lines", value: lineSummary)
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
            if let diffPreview = nonEmpty(
                event.payload["diffPreview"]
                    ?? event.payload["diff"]
                    ?? event.payload["patch"]
                    ?? event.payload["unified_diff"]
                    ?? event.payload["changes_preview"]
            ) {
                diffField(label: "Diff preview", value: diffPreview)
            }
            if let status = event.payload["status"], !status.isEmpty {
                detailField(label: "Status", value: status)
            }
            if let priority = event.payload["priority"], !priority.isEmpty {
                detailField(label: "Priority", value: priority)
            }
            if let notes = event.payload["notes"], !notes.isEmpty {
                detailField(label: "Notes", value: notes)
            }
            if let files = event.payload["files"], !files.isEmpty {
                detailField(label: "Files", value: files)
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
                .lineLimit(nil)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.55))
                )
        }
    }

    @ViewBuilder
    private func diffField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(buildDiffAttributed(value))
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.55))
                )
        }
    }

    /// Builds a single colored `AttributedString` for the entire diff, avoiding N separate `Text` views.
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
            return NSColor(DesignSystem.Colors.textTertiary)
        }
        if line.hasPrefix("+") {
            return NSColor(DesignSystem.Colors.success)
        }
        if line.hasPrefix("-") {
            return NSColor(DesignSystem.Colors.error)
        }
        return NSColor(DesignSystem.Colors.textSecondary)
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
                return String(text.prefix(180))
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

    private func collapsedSummaryText(derived: DerivedState) -> String {
        let orderedEvents = derived.orderedEvents
        let fileCount = inferredFileCount(from: orderedEvents)
        let readCount = inferredReadCount(from: orderedEvents)
        let searchCount = inferredSearchCount(from: orderedEvents)
        let commandCount = inferredCommandCount(from: orderedEvents)
        let editCount = inferredEditCount(from: orderedEvents)
        let mcpSummary = inferredMCPSummary(from: orderedEvents)
        let skillSummary = inferredSkillsSummary(from: orderedEvents)

        if (readCount > 0 || fileCount > 0) && searchCount > 0 {
            let exploredCount = max(fileCount, readCount)
            var base = "Explored \(exploredCount) \(pluralized("file", count: exploredCount)), \(searchCount) \(pluralized("search", count: searchCount))"
            if let mcpSummary {
                base += " • \(mcpSummary)"
            }
            if let skillSummary {
                base += " • \(skillSummary)"
            }
            return base
        }

        var parts: [String] = []
        if readCount > 0 {
            parts.append("\(readCount) \(pluralized("read", count: readCount))")
        }
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

    private func inferredFileCount(from orderedEvents: [ToolTraceEvent]) -> Int {
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

    private func inferredReadCount(from orderedEvents: [ToolTraceEvent]) -> Int {
        orderedEvents.filter { event in
            let type = event.type.lowercased()
            if type == "read_batch_started" || type == "read_batch_completed" {
                return true
            }
            if type == "semantic_search" {
                return true
            }
            return (event.payload["source"] ?? "") == "synthetic_command_read"
        }.count
    }

    private func inferredSearchCount(from orderedEvents: [ToolTraceEvent]) -> Int {
        orderedEvents.filter { event in
            let type = event.type.lowercased()
            return type.contains("search") || type.contains("grep")
                || type == "instant_grep"
        }.count
    }

    private func inferredCommandCount(from orderedEvents: [ToolTraceEvent]) -> Int {
        orderedEvents.filter { event in
            let type = event.type.lowercased()
            return type == "bash" || type == "command_execution"
        }.count
    }

    private func inferredEditCount(from orderedEvents: [ToolTraceEvent]) -> Int {
        orderedEvents.filter { ToolTraceFileChangeMapper.isFileChangeEvent($0) }.count
    }

    private func inferredMCPSummary(from orderedEvents: [ToolTraceEvent]) -> String? {
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

    private func inferredSkillsSummary(from orderedEvents: [ToolTraceEvent]) -> String? {
        let skills = inferredSkillNames(from: orderedEvents)
        guard !skills.isEmpty else { return nil }
        if skills.count <= 2 {
            return "Skills: \(skills.joined(separator: ", "))"
        }
        return "Skills: \(skills.prefix(2).joined(separator: ", ")) +\(skills.count - 2)"
    }

    private func inferredSkillNames(from orderedEvents: [ToolTraceEvent]) -> [String] {
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

    private func collapseSupersededToolStates(_ input: [ToolTraceEvent]) -> [ToolTraceEvent] {
        var latestByToolCall: [String: ToolTraceEvent] = [:]
        var passthrough: [ToolTraceEvent] = []

        for event in input {
            let toolCallId = (event.payload["tool_call_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if toolCallId.isEmpty {
                passthrough.append(event)
                continue
            }
            latestByToolCall[toolCallId] = event
        }

        let collapsed = Array(latestByToolCall.values)
        let merged = passthrough + collapsed
        return merged.sorted {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.timestamp < $1.timestamp
        }
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

    private func loadCompactDiffPreviewIfNeeded() {
        guard !isCompactDiffLoading else { return }
        let changes = computeFileChanges()
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
                let updatedChanges = computeFileChanges()
                if isExpanded, compactDiffPreview(fileChanges: updatedChanges) != nil {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isCompactDiffExpanded = true
                    }
                }
            }
        }
    }

    /// Lightweight helper for out-of-body contexts (e.g. onChange, tasks).
    private func computeOrderedEvents() -> [ToolTraceEvent] {
        let filtered = events
            .filter { ToolTraceVisibility.shouldDisplay(event: $0) }
            .sorted { lhs, rhs in
                if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
                return lhs.timestamp < rhs.timestamp
            }
        return collapseSupersededToolStates(filtered)
    }

    private func computeFileChanges() -> [ToolTraceFileChange] {
        ToolTraceFileChangeMapper.collect(from: computeOrderedEvents())
    }

    private func syncAutoPresentationState() {
        let ordered = computeOrderedEvents()
        let running = ordered.contains(where: \.isRunning)
        if running {
            didAutoCompactAfterCompletion = false
            return
        }
        guard !ordered.isEmpty else { return }
        guard !didAutoCompactAfterCompletion else { return }
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
