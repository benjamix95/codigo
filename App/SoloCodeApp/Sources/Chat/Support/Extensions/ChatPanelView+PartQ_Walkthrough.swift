import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func buildWalkthroughMarkdown(
        canonicalTodos: [TodoItem],
        planBoard: PlanBoard?,
        agentMessages: [ChatMessage] = [],
        traceEvents: [ToolTraceEvent] = []
    ) -> String {
        var lines: [String] = ["## Build Complete", ""]
        if let goal = planBoard?.goal, !goal.isEmpty {
            lines.append("**Objective:** \(goal)")
            lines.append("")
        }

        let doneCount = canonicalTodos.filter { $0.status == .done }.count
        lines.append("### Steps (\(doneCount)/\(canonicalTodos.count) completed)")
        if canonicalTodos.isEmpty {
            lines.append("- No canonical steps recorded for this build.")
        } else {
            for todo in canonicalTodos {
                let icon = todo.status == .done ? "x" : " "
                lines.append("- [\(icon)] \(todo.title)")
                if !todo.linkedFiles.isEmpty {
                    lines.append("  Files: \(todo.linkedFiles.joined(separator: ", "))")
                }
            }
        }
        lines.append("")

        let changedFiles = touchedFilePathsFromTraceEvents(traceEvents, maxCount: 200)
        if !changedFiles.isEmpty {
            lines.append("### Files Modified (\(changedFiles.count))")
            for file in changedFiles {
                lines.append("- `\(file)`")
            }
            lines.append("")
        }

        let commands = traceEvents
            .filter { $0.type == "command_execution" }
            .compactMap { $0.payload["command"] ?? $0.title }
            .filter { !$0.isEmpty }
        if !commands.isEmpty {
            let uniqueCommands = Array(Set(commands.map { cmd in
                cmd.count > 80 ? String(cmd.prefix(77)) + "..." : cmd
            })).sorted().prefix(10)
            lines.append("### Commands Executed")
            for cmd in uniqueCommands {
                lines.append("- `\(cmd)`")
            }
            lines.append("")
        }

        let narrativeBlocks = agentMessages
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { $0.count > 40 }
        if !narrativeBlocks.isEmpty {
            lines.append("### Execution Details")
            let combined = narrativeBlocks.joined(separator: "\n\n---\n\n")
            let capped = combined.count > 6000 ? String(combined.suffix(6000)) : combined
            lines.append(capped)
        }

        return lines.joined(separator: "\n")
    }
}
