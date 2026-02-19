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

    static func build(from planContent: String, options: [PlanOption]) -> PlanBoard {
        let goal = PlanBoard.extractGoal(from: planContent)
        let steps = PlanBoard.extractSteps(from: planContent)
        return PlanBoard(goal: goal, options: options, chosenPath: nil, steps: steps, updatedAt: .now)
    }

    private static func extractGoal(from text: String) -> String {
        let lines = text.split(separator: "\n").map(String.init)
        if let firstHeader = lines.first(where: { $0.hasPrefix("#") }) {
            return firstHeader.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        }
        return String(text.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractSteps(from text: String) -> [PlanStep] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var steps: [PlanStep] = []
        let regex = try? NSRegularExpression(pattern: #"^\s*(\d+)[.)]\s+(.+)$"#)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let regex,
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let idRange = Range(match.range(at: 1), in: trimmed),
               let titleRange = Range(match.range(at: 2), in: trimmed) {
                let rawId = String(trimmed[idRange])
                let full = String(trimmed[titleRange])
                steps.append(PlanStep(id: rawId, title: full, description: full, targetFile: nil, status: .pending))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let full = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let newId = "b\(steps.count + 1)"
                steps.append(PlanStep(id: newId, title: full, description: full, targetFile: nil, status: .pending))
            }
        }

        if steps.isEmpty {
            steps.append(PlanStep(id: "1", title: "Esecuzione piano", description: "Seguire il piano proposto", targetFile: nil, status: .pending))
        }
        return steps
    }
}
