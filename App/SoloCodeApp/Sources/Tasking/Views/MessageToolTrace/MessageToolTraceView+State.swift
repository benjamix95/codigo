import SwiftUI

extension MessageToolTraceView {
    struct DerivedState {
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
            let visible = events
                .filter { ToolTraceVisibility.shouldDisplay(event: $0) }
            let maxEventsToProcess = isExpanded ? 120 : max(60, runningCompactLimit * 4)
            let boundedVisible: [ToolTraceEvent]
            if visible.count > maxEventsToProcess {
                boundedVisible = Array(visible.suffix(maxEventsToProcess))
            } else {
                boundedVisible = visible
            }
            let filtered = boundedVisible
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

        static func computeCollapsedSummary(orderedEvents: [ToolTraceEvent]) -> String {
            var filePaths = Set<String>()
            var readCount = 0
            var searchCount = 0
            var listCount = 0
            var commandCount = 0
            var editCount = 0
            var mcpCount = 0
            var mcpToolNames = Set<String>()
            var browserCount = 0
            var skillNames = Set<String>()

            for event in orderedEvents {
                if let path = event.payload["path"], !path.isEmpty { filePaths.insert(path) }
                if let file = event.payload["file"], !file.isEmpty { filePaths.insert(file) }
                let type = event.type.lowercased()
                let tool = (
                    event.payload["mcp_tool"]
                        ?? event.payload["mcpTool"]
                        ?? event.payload["tool"]
                        ?? event.payload["name"]
                        ?? ""
                ).lowercased()
                if type == "read_batch_completed"
                    || (event.payload["source"] ?? "") == "synthetic_command_read"
                    || tool == "read" || tool == "read_range"
                {
                    readCount += 1
                }
                if type.contains("search") || type.contains("grep") || type == "instant_grep"
                    || tool == "grep" || tool == "search" || tool == "codebase_search"
                    || tool == "semantic_search" || tool == "find_symbol" || tool == "find_references"
                {
                    searchCount += 1
                }
                if type.contains("glob") || tool == "glob" || tool == "list_dir" || tool == "find_files" {
                    listCount += 1
                }
                if type == "bash" || type == "command_execution" { commandCount += 1 }
                if ToolTraceFileChangeMapper.isFileChangeEvent(event) { editCount += 1 }
                if ToolTraceVisibility.isMCPEvent(event: event) {
                    mcpCount += 1
                    mcpToolNames.insert(userFacingToolName(from: event.payload))
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
            if editCount > 0 { parts.append("\(editCount) \(pluralized("modifica", count: editCount, plural: "modifiche"))") }
            if readCount > 0 || fileCount > 0 {
                let readFileCount = max(fileCount, readCount)
                let readFileLabel = readFileCount == 1 ? "file letto" : "file letti"
                parts.append("\(readFileCount) \(readFileLabel)")
            }
            if searchCount > 0 { parts.append("\(searchCount) \(pluralized("ricerca", count: searchCount, plural: "ricerche"))") }
            if listCount > 0 { parts.append("\(listCount) \(pluralized("elenco", count: listCount, plural: "elenchi"))") }
            if commandCount > 0 { parts.append("\(commandCount) \(pluralized("comando", count: commandCount, plural: "comandi"))") }
            if mcpCount > 0 {
                let tools = mcpToolNames.sorted()
                if tools.count <= 2 {
                    parts.append(tools.joined(separator: ", "))
                } else {
                    parts.append("\(tools.prefix(2).joined(separator: ", ")) +\(tools.count - 2)")
                }
            }
            if browserCount > 0 {
                parts.append("\(browserCount) \(pluralized("azione browser", count: browserCount, plural: "azioni browser"))")
            }
            if !skillNames.isEmpty {
                let skills = skillNames.sorted()
                parts.append(skills.count <= 2 ? "Skill: \(skills.joined(separator: ", "))" : "Skill: \(skills.prefix(2).joined(separator: ", ")) +\(skills.count - 2)")
            }
            if !parts.isEmpty { return parts.prefix(3).joined(separator: " \u{00B7} ") }
            return "\(orderedEvents.count) \(pluralized("operazione", count: orderedEvents.count, plural: "operazioni"))"
        }

        static func skillPathCandidates(for event: ToolTraceEvent) -> [String] {
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

        static func extractSkillName(from raw: String) -> String? {
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

        static func isErrorEvent(_ event: ToolTraceEvent) -> Bool {
            let type = event.type.lowercased()
            let status = (event.payload["status"] ?? "").lowercased()
            if MessageToolTraceView.hardErrorTypes.contains(type) || type.contains("error") {
                return true
            }
            // Non-zero exits often surface as "failed" status for command-like tools.
            // Keep them out of global error badges unless explicitly marked as error.
            return status == "error" || status == "fatal"
        }

        static func isWarningEvent(_ event: ToolTraceEvent) -> Bool {
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

    nonisolated static let hardErrorTypes: Set<String> = [
        "error",
        "permission_denied",
        "tool_execution_error",
        "tool_timeout",
        "tool_validation_error",
        "web_fetch_failed",
        "web_search_failed",
    ]

    final class DerivedCache {
        var state: DerivedState?
        var isExpanded: Bool = false
        var changeToken: EventsChangeToken = .empty
    }
    struct EventsChangeToken: Equatable {
        let count: Int
        let firstId: UUID?
        let firstSequence: Int
        let firstRunning: Bool
        let lastId: UUID?
        let lastSequence: Int
        let lastRunning: Bool
        let lastStatus: String
        let lastDetail: String

        static let empty = EventsChangeToken(
            count: -1,
            firstId: nil,
            firstSequence: -1,
            firstRunning: false,
            lastId: nil,
            lastSequence: -1,
            lastRunning: false,
            lastStatus: "",
            lastDetail: ""
        )
    }

    var eventsChangeToken: EventsChangeToken {
        let first = events.first
        let last = events.last
        return EventsChangeToken(
            count: events.count,
            firstId: first?.id,
            firstSequence: first?.sequence ?? -1,
            firstRunning: first?.isRunning ?? false,
            lastId: last?.id,
            lastSequence: last?.sequence ?? -1,
            lastRunning: last?.isRunning ?? false,
            lastStatus: last?.payload["status"] ?? "",
            lastDetail: last?.detail ?? ""
        )
    }

    func currentDerived() -> DerivedState {
        let token = eventsChangeToken
        if let cached = derivedCache.state,
           isExpanded == derivedCache.isExpanded,
           token == derivedCache.changeToken {
            return cached
        }
        let d = DerivedState(
            events: events,
            isExpanded: isExpanded,
            runningCompactLimit: runningCompactLimit,
            collapser: collapseSupersededToolStates
        )
        derivedCache.state = d
        derivedCache.isExpanded = isExpanded
        derivedCache.changeToken = token
        return d
    }
}
