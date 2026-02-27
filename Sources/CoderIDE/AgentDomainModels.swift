import Foundation

struct InstantGrepMatch: Identifiable, Codable {
    let id: UUID
    let file: String
    let line: Int
    let preview: String

    init(id: UUID = UUID(), file: String, line: Int, preview: String) {
        self.id = id
        self.file = file
        self.line = line
        self.preview = preview
    }
}

struct InstantGrepResult: Identifiable, Codable {
    let id: UUID
    let query: String
    let scope: String
    let matchesCount: Int
    let durationMs: Int?
    let matches: [InstantGrepMatch]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        query: String,
        scope: String,
        matchesCount: Int,
        durationMs: Int? = nil,
        matches: [InstantGrepMatch],
        createdAt: Date = .now
    ) {
        self.id = id
        self.query = query
        self.scope = scope
        self.matchesCount = matchesCount
        self.durationMs = durationMs
        self.matches = matches
        self.createdAt = createdAt
    }
}

enum PlanStepStatus: String, Codable {
    case pending
    case running
    case done
    case failed
}

struct PlanStep: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var description: String
    var targetFile: String?
    var status: PlanStepStatus
}

struct PlanBoard: Codable, Equatable {
    var goal: String
    var options: [PlanOption]
    var chosenPath: String?
    var steps: [PlanStep]
    var updatedAt: Date
    /// Walkthrough markdown generated when the plan completes (Antigravity-style summary)
    var walkthroughMarkdown: String?

    static func build(from planContent: String, options: [PlanOption]) -> PlanBoard {
        let goal = PlanBoard.extractGoal(from: planContent)
        let primaryOption = options.min(by: { $0.id < $1.id })
        let initialTodos = primaryOption.map { PlanOptionsParser.extractTodosFromOptionText($0.fullText) } ?? []
        let steps = PlanBoard.buildSteps(fromTodoTitles: initialTodos)
        return PlanBoard(goal: goal, options: options, chosenPath: nil, steps: steps, updatedAt: .now, walkthroughMarkdown: nil)
    }

    private static func extractGoal(from text: String) -> String {
        let lines = text.split(separator: "\n").map(String.init)
        if let firstHeader = lines.first(where: { $0.hasPrefix("#") }) {
            // Strip only leading '#' characters (markdown header prefix),
            // not '#' appearing mid-text (e.g. "C#", "F#").
            let stripped = firstHeader.drop(while: { $0 == "#" })
            return String(stripped).trimmingCharacters(in: .whitespaces)
        }
        return String(text.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func buildSteps(
        fromTodoTitles titles: [String],
        statusForIndex: ((Int) -> PlanStepStatus)? = nil
    ) -> [PlanStep] {
        let cleaned = titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if cleaned.isEmpty {
            return [
                PlanStep(
                    id: "1",
                    title: "Plan execution",
                    description: "Follow the proposed plan",
                    targetFile: nil,
                    status: .pending
                )
            ]
        }

        return cleaned.enumerated().map { index, title in
            PlanStep(
                id: String(index + 1),
                title: title,
                description: title,
                targetFile: nil,
                status: statusForIndex?(index) ?? .pending
            )
        }
    }
}
