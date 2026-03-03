import Foundation

public struct MCPSharedPlanStep: Codable, Equatable {
    public var id: String
    public var title: String
    public var description: String
    public var targetFile: String?
    public var status: String
    public var linkedFiles: [String]
    public var dependsOn: [String]
    public var notes: String
    public var updatedAt: String

    public init(
        id: String,
        title: String,
        description: String,
        targetFile: String?,
        status: String,
        linkedFiles: [String],
        dependsOn: [String],
        notes: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.targetFile = targetFile
        self.status = status
        self.linkedFiles = linkedFiles
        self.dependsOn = dependsOn
        self.notes = notes
        self.updatedAt = updatedAt
    }
}

public struct MCPSharedPlanSnapshot: Codable, Equatable {
    public var snapshotId: String
    public var conversationId: String
    public var goal: String
    public var chosenPath: String?
    public var steps: [MCPSharedPlanStep]
    public var walkthroughMarkdown: String?
    public var summary: String?
    public var outcome: String?
    public var createdAt: String
    public var updatedAt: String

    public init(
        snapshotId: String,
        conversationId: String,
        goal: String,
        chosenPath: String?,
        steps: [MCPSharedPlanStep],
        walkthroughMarkdown: String?,
        summary: String?,
        outcome: String?,
        createdAt: String,
        updatedAt: String
    ) {
        self.snapshotId = snapshotId
        self.conversationId = conversationId
        self.goal = goal
        self.chosenPath = chosenPath
        self.steps = steps
        self.walkthroughMarkdown = walkthroughMarkdown
        self.summary = summary
        self.outcome = outcome
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MCPSharedPlanStateDocument: Codable, Equatable {
    public var version: Int
    public var latestConversationId: String?
    public var snapshotsByConversation: [String: [MCPSharedPlanSnapshot]]

    public init(
        version: Int = 1,
        latestConversationId: String? = nil,
        snapshotsByConversation: [String: [MCPSharedPlanSnapshot]] = [:]
    ) {
        self.version = version
        self.latestConversationId = latestConversationId
        self.snapshotsByConversation = snapshotsByConversation
    }
}

public struct MCPSharedPlanStatusChange: Codable, Equatable {
    public var stepId: String
    public var title: String
    public var fromStatus: String
    public var toStatus: String

    public init(stepId: String, title: String, fromStatus: String, toStatus: String) {
        self.stepId = stepId
        self.title = title
        self.fromStatus = fromStatus
        self.toStatus = toStatus
    }
}

public struct MCPSharedPlanDiffResult: Codable, Equatable {
    public var fromSnapshotId: String
    public var toSnapshotId: String
    public var goalChanged: Bool
    public var addedSteps: [MCPSharedPlanStep]
    public var removedSteps: [MCPSharedPlanStep]
    public var statusChanges: [MCPSharedPlanStatusChange]

    public init(
        fromSnapshotId: String,
        toSnapshotId: String,
        goalChanged: Bool,
        addedSteps: [MCPSharedPlanStep],
        removedSteps: [MCPSharedPlanStep],
        statusChanges: [MCPSharedPlanStatusChange]
    ) {
        self.fromSnapshotId = fromSnapshotId
        self.toSnapshotId = toSnapshotId
        self.goalChanged = goalChanged
        self.addedSteps = addedSteps
        self.removedSteps = removedSteps
        self.statusChanges = statusChanges
    }
}
