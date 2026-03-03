import SwiftUI

enum TodoStatus: String, Codable, CaseIterable {
    case pending
    case inProgress = "in_progress"
    case blocked
    case done

    var rank: Int {
        switch self {
        case .inProgress: return 0
        case .pending: return 1
        case .blocked: return 2
        case .done: return 3
        }
    }

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "circle.inset.filled"
        case .blocked: return "exclamationmark.circle"
        case .done: return "checkmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .pending: return "OPEN"
        case .inProgress: return "DOING"
        case .blocked: return "BLOCKED"
        case .done: return "DONE"
        }
    }

    var color: Color {
        switch self {
        case .pending: return DesignSystem.Colors.textSecondary
        case .inProgress: return DesignSystem.Colors.planColor
        case .blocked: return DesignSystem.Colors.error
        case .done: return DesignSystem.Colors.success
        }
    }
}

enum TodoPriority: String, Codable, CaseIterable {
    case low
    case medium
    case high

    var rank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }

    var color: Color {
        switch self {
        case .low: return DesignSystem.Colors.textTertiary
        case .medium: return DesignSystem.Colors.info
        case .high: return DesignSystem.Colors.error
        }
    }
}

enum TodoSource: String, Codable {
    case manual
    case agent
}

struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var status: TodoStatus
    var priority: TodoPriority
    var source: TodoSource
    let createdAt: Date
    var updatedAt: Date
    var notes: String
    var linkedFiles: [String]
    var isPlanCanonical: Bool
    /// Conversation that owns this canonical plan todo.
    var planConversationId: UUID?
    /// Present-tense label shown during execution (e.g. "Fixing bug").
    var activeForm: String

    init(
        id: UUID = UUID(),
        title: String,
        status: TodoStatus = .pending,
        priority: TodoPriority = .medium,
        source: TodoSource = .manual,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        notes: String = "",
        linkedFiles: [String] = [],
        isPlanCanonical: Bool = false,
        planConversationId: UUID? = nil,
        activeForm: String = ""
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.linkedFiles = linkedFiles
        self.isPlanCanonical = isPlanCanonical
        self.planConversationId = planConversationId
        self.activeForm = activeForm
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, completed, status, priority, source, createdAt, updatedAt, notes, linkedFiles, isPlanCanonical, planConversationId, activeForm
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? .now

        if let parsedStatus = try? container.decode(TodoStatus.self, forKey: .status) {
            status = parsedStatus
        } else {
            let completed = (try? container.decode(Bool.self, forKey: .completed)) ?? false
            status = completed ? .done : .pending
        }

        priority = (try? container.decode(TodoPriority.self, forKey: .priority)) ?? .medium
        source = (try? container.decode(TodoSource.self, forKey: .source)) ?? .manual
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        linkedFiles = (try? container.decode([String].self, forKey: .linkedFiles)) ?? []
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        isPlanCanonical = (try? container.decode(Bool.self, forKey: .isPlanCanonical)) ?? false
        if let parsedConversationId = try? container.decode(UUID.self, forKey: .planConversationId) {
            planConversationId = parsedConversationId
        } else if let legacyConversationId = try? container.decode(String.self, forKey: .planConversationId),
                  let parsed = UUID(uuidString: legacyConversationId.trimmingCharacters(in: .whitespacesAndNewlines)) {
            planConversationId = parsed
        } else {
            planConversationId = nil
        }
        activeForm = (try? container.decode(String.self, forKey: .activeForm)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(source, forKey: .source)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(notes, forKey: .notes)
        try container.encode(linkedFiles, forKey: .linkedFiles)
        try container.encode(isPlanCanonical, forKey: .isPlanCanonical)
        try container.encodeIfPresent(planConversationId, forKey: .planConversationId)
        try container.encode(activeForm, forKey: .activeForm)
    }
}

enum TodoFilter: String, CaseIterable {
    case open = "Aperti"
    case inProgress = "In corso"
    case completed = "Completed"
}

let todosStorageKey = "CoderIDE.todos"
