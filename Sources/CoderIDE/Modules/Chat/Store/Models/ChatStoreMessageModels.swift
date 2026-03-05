import Foundation
import CoderEngine

struct PlanAttachment: Codable, Equatable {
    var historyEntryId: UUID
    var layoutVersion: Int
    var showExpand: Bool
    var snapshotTitle: String
}

/// Lightweight, codable snapshot of a subagent card persisted inside a ChatMessage.
struct SubagentCardSnapshot: Codable, Identifiable, Equatable {
    var id: String { swarmId }
    let swarmId: String
    let status: SwarmCardStatus
    let title: String
    let detail: String
    let summary: String?
    let errorCount: Int
    let warningCount: Int?
    let resultPreview: String?

    init(from card: SwarmLiveCardState) {
        self.swarmId = card.swarmId
        self.status = card.status
        self.title = card.displayName.isEmpty ? card.currentStepTitle : card.displayName
        self.detail = card.currentDetail
        self.summary = card.summary
        self.errorCount = card.errorCount
        self.warningCount = card.warningCount
        self.resultPreview = Self.extractPreview(from: card.liveText)
    }

    private static func extractPreview(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let lastLines = lines.suffix(8).joined(separator: "\n")
        return String(lastLines.suffix(500))
    }
}

enum ChatAttachmentKind: String, Codable {
    case image
    case document
    case file
}

struct ChatAttachment: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ChatAttachmentKind
    var originalName: String
    var mimeType: String?
    var localPath: String
    var sizeBytes: Int64?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: ChatAttachmentKind,
        originalName: String,
        mimeType: String? = nil,
        localPath: String,
        sizeBytes: Int64? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.originalName = originalName
        self.mimeType = mimeType
        self.localPath = localPath
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
    }
}

struct ChatMessage: Identifiable, Codable {
    var id: UUID
    var role: Role
    var content: String
    var isStreaming: Bool
    var imagePaths: [String]?
    var attachments: [ChatAttachment]?
    var planAttachment: PlanAttachment?
    var reasoningText: String?
    var subagentCards: [SubagentCardSnapshot]?

    enum Role: String, Codable {
        case user
        case assistant
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        isStreaming: Bool = false,
        imagePaths: [String]? = nil,
        attachments: [ChatAttachment]? = nil,
        planAttachment: PlanAttachment? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.imagePaths = imagePaths
        if let attachments {
            self.attachments = attachments
        } else if let imagePaths, !imagePaths.isEmpty {
            self.attachments = imagePaths.map { path in
                ChatAttachment(
                    kind: .image,
                    originalName: URL(fileURLWithPath: path).lastPathComponent,
                    mimeType: nil,
                    localPath: path
                )
            }
        } else {
            self.attachments = nil
        }
        self.planAttachment = planAttachment
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, isStreaming, imagePaths, attachments, planAttachment, reasoningText, subagentCards
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        isStreaming = (try? c.decode(Bool.self, forKey: .isStreaming)) ?? false
        imagePaths = try? c.decode([String].self, forKey: .imagePaths)
        let decodedAttachments = try? c.decode([ChatAttachment].self, forKey: .attachments)
        if let decodedAttachments, !decodedAttachments.isEmpty {
            attachments = decodedAttachments
        } else if let imagePaths, !imagePaths.isEmpty {
            attachments = imagePaths.map { path in
                ChatAttachment(
                    kind: .image,
                    originalName: URL(fileURLWithPath: path).lastPathComponent,
                    mimeType: nil,
                    localPath: path
                )
            }
        } else {
            attachments = nil
        }
        planAttachment = try? c.decode(PlanAttachment.self, forKey: .planAttachment)
        reasoningText = try? c.decode(String.self, forKey: .reasoningText)
        subagentCards = try? c.decode([SubagentCardSnapshot].self, forKey: .subagentCards)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        try c.encode(isStreaming, forKey: .isStreaming)
        try c.encodeIfPresent(planAttachment, forKey: .planAttachment)
        try c.encodeIfPresent(attachments, forKey: .attachments)
        let legacyImagePaths = imagePaths ?? attachments?
            .filter { $0.kind == .image }
            .map(\.localPath)
        try c.encodeIfPresent(legacyImagePaths, forKey: .imagePaths)
        try c.encodeIfPresent(reasoningText, forKey: .reasoningText)
        try c.encodeIfPresent(subagentCards, forKey: .subagentCards)
    }
}
