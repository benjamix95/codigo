import Foundation

@MainActor
final class PlanHistoryStore: ObservableObject {
    @Published var entries: [PlanHistoryEntry] = []
    @Published var selectedEntryIdByConversation: [UUID: UUID] = [:]
    @Published var selectedEntryId: UUID?
    private var userDefaultsObserver: NSObjectProtocol?
    let userDefaults: UserDefaults
    let storageURL: URL

    private var planBoardObserver: NSObjectProtocol?

    init(
        userDefaults: UserDefaults = .standard,
        storageURL: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.storageURL = storageURL ?? Self.defaultFileURL
        load()
        applyConfiguredLimits()
        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: userDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyConfiguredLimits()
            }
        }
        planBoardObserver = NotificationCenter.default.addObserver(
            forName: .planBoardDidPersist,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleBoardPersisted(notification)
            }
        }
    }

    deinit {
        if let observer = userDefaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = planBoardObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// When a plan board is persisted, update the matching history entry's
    /// markdown and re-write the `.solocode/plan/` file.
    private func handleBoardPersisted(_ notification: Notification) {
        guard let convId = notification.userInfo?["conversationId"] as? UUID,
              let board = notification.userInfo?["board"] as? PlanBoard
        else { return }
        guard let idx = entries.firstIndex(where: { $0.conversationId == convId })
        else { return }
        let markdown = boardToMarkdown(board)
        entries[idx].markdown = String(markdown.prefix(configuredMaxMarkdownLength))
        entries[idx].updatedAt = .now
        save()
        writePlanFile(entry: entries[idx])
    }

    /// Convert a PlanBoard to a readable markdown snapshot including
    /// mermaid diagrams, steps with dependencies, and todo checklist.
    private func boardToMarkdown(_ board: PlanBoard) -> String {
        var lines: [String] = []
        lines.append("# \(board.goal)")
        if let path = board.chosenPath, !path.isEmpty {
            lines.append("\n**Approach:** \(path)")
        }

        // ── Mermaid dependency graph ──────────────────────────
        let stepsWithDeps = board.steps.filter { !$0.dependsOn.isEmpty }
        if !stepsWithDeps.isEmpty || board.steps.count > 1 {
            lines.append("\n## Dependency Graph\n")
            lines.append("```mermaid")
            lines.append("graph TD")
            for step in board.steps {
                let label = step.title
                    .replacingOccurrences(of: "\"", with: "'")
                let statusIcon = step.status == .done ? " ✅"
                    : step.status == .running ? " 🔄"
                    : step.status == .failed ? " ❌" : ""
                lines.append("    \(step.id)[\"\(label)\(statusIcon)\"]")
            }
            for step in board.steps {
                for dep in step.dependsOn {
                    lines.append("    \(dep) --> \(step.id)")
                }
            }
            // Style completed steps
            let doneIds = board.steps
                .filter { $0.status == .done }
                .map(\.id)
            if !doneIds.isEmpty {
                lines.append("    style \(doneIds.joined(separator: ",")) fill:#2d6a2e,stroke:#4CAF50")
            }
            lines.append("```")
        }

        // ── Detailed Steps ───────────────────────────────────
        lines.append("\n## Steps\n")
        for (i, step) in board.steps.enumerated() {
            let checkbox = step.status == .done ? "[x]" : "[ ]"
            let statusTag: String
            switch step.status {
            case .running: statusTag = " `RUNNING`"
            case .failed: statusTag = " `FAILED`"
            default: statusTag = ""
            }
            lines.append("- \(checkbox) **\(i + 1). \(step.title)**\(statusTag)")
            if !step.description.isEmpty {
                lines.append("  \(step.description)")
            }
            if let file = step.targetFile, !file.isEmpty {
                lines.append("  - Target: `\(file)`")
            }
            if !step.linkedFiles.isEmpty {
                lines.append("  - Files: \(step.linkedFiles.map { "`\($0)`" }.joined(separator: ", "))")
            }
            if !step.dependsOn.isEmpty {
                lines.append("  - Depends on: \(step.dependsOn.joined(separator: ", "))")
            }
            if !step.notes.isEmpty {
                lines.append("  - Notes: \(step.notes)")
            }
        }

        // ── Todo checklist (compact) ─────────────────────────
        lines.append("\n## Todo Checklist\n")
        for step in board.steps {
            let mark = step.status == .done ? "x" : " "
            lines.append("- [\(mark)] \(step.title)")
        }

        // ── Progress ─────────────────────────────────────────
        let done = board.steps.filter { $0.status == .done }.count
        let total = board.steps.count
        if total > 0 {
            let pct = Int(Double(done) / Double(total) * 100)
            lines.append("\n**Progress:** \(done)/\(total) (\(pct)%)")
        }

        // ── Summary / Walkthrough ────────────────────────────
        if let walkthrough = board.walkthroughMarkdown, !walkthrough.isEmpty {
            lines.append("\n## Summary\n\(walkthrough)")
        }
        if let outcome = board.walkthroughOutcome, !outcome.isEmpty {
            lines.append("\n**Outcome:** \(outcome)")
        }

        return lines.joined(separator: "\n")
    }
}
