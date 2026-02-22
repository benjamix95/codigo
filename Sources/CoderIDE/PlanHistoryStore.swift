import Foundation

struct PlanHistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var conversationId: UUID
    var contextId: UUID?
    var contextFolderPath: String?
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var markdown: String
    var options: [PlanOption]
    var chosenPath: String?
    var tags: [String]
    var sourceMessageId: UUID?
    var isPinned: Bool
    var rebuildCount: Int
    var lastBuildAt: Date?

    init(
        id: UUID = UUID(),
        conversationId: UUID,
        contextId: UUID?,
        contextFolderPath: String?,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        title: String,
        markdown: String,
        options: [PlanOption],
        chosenPath: String?,
        tags: [String] = [],
        sourceMessageId: UUID? = nil,
        isPinned: Bool = false,
        rebuildCount: Int = 0,
        lastBuildAt: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.contextId = contextId
        self.contextFolderPath = contextFolderPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.markdown = markdown
        self.options = options
        self.chosenPath = chosenPath
        self.tags = tags
        self.sourceMessageId = sourceMessageId
        self.isPinned = isPinned
        self.rebuildCount = rebuildCount
        self.lastBuildAt = lastBuildAt
    }
}

private let planHistoryStorageKey = "CoderIDE.planHistory"
private let maxPlanHistoryEntries = 200
private let maxPlanMarkdownLength = 65_536
private let maxPlanOptionsPersisted = 8
private let maxPlanTitleLength = 120

@MainActor
final class PlanHistoryStore: ObservableObject {
    @Published private(set) var entries: [PlanHistoryEntry] = []
    @Published var selectedEntryId: UUID?

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: planHistoryStorageKey),
              let decoded = try? JSONDecoder().decode([PlanHistoryEntry].self, from: data) else {
            return
        }
        entries = Array(decoded.sorted(by: { $0.createdAt > $1.createdAt }).prefix(maxPlanHistoryEntries))
    }

    func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: planHistoryStorageKey)
    }

    private func sanitizeTitle(_ raw: String) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Piano"
        }
        return String(trimmed.prefix(maxPlanTitleLength))
    }

    @discardableResult
    func createEntry(
        conversationId: UUID,
        contextId: UUID?,
        contextFolderPath: String?,
        title: String,
        markdown: String,
        options: [PlanOption],
        chosenPath: String?,
        tags: [String],
        sourceMessageId: UUID?
    ) -> PlanHistoryEntry {
        let sanitizedMarkdown = String(markdown.prefix(maxPlanMarkdownLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cappedOptions = Array(options.prefix(maxPlanOptionsPersisted))
        let safeTitle = sanitizeTitle(title)
        let safeMarkdown = sanitizedMarkdown.isEmpty
            ? "Piano non disponibile (contenuto vuoto)."
            : sanitizedMarkdown
        let entry = PlanHistoryEntry(
            conversationId: conversationId,
            contextId: contextId,
            contextFolderPath: contextFolderPath,
            title: safeTitle,
            markdown: safeMarkdown,
            options: cappedOptions,
            chosenPath: chosenPath,
            tags: tags,
            sourceMessageId: sourceMessageId
        )
        entries.append(entry)
        if entries.count > maxPlanHistoryEntries {
            entries = Array(entries.sorted(by: { $0.createdAt > $1.createdAt }).prefix(maxPlanHistoryEntries))
        }
        selectedEntryId = entry.id
        save()
        return entry
    }

    func findEntry(id: UUID?) -> PlanHistoryEntry? {
        guard let id else { return nil }
        return entries.first(where: { $0.id == id })
    }

    func findEntry(conversationId: UUID, sourceMessageId: UUID) -> PlanHistoryEntry? {
        entries.first(where: { $0.conversationId == conversationId && $0.sourceMessageId == sourceMessageId })
    }

    @discardableResult
    func duplicateEntry(id: UUID) -> PlanHistoryEntry? {
        guard var copy = findEntry(id: id) else { return nil }
        copy.id = UUID()
        copy.createdAt = .now
        copy.updatedAt = .now
        copy.sourceMessageId = nil
        entries.append(copy)
        selectedEntryId = copy.id
        save()
        return copy
    }

    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        if selectedEntryId == id { selectedEntryId = nil }
        save()
    }

    /// Elimina tutti i planning per il contesto indicato (o tutti se nil).
    func deleteAllForContext(contextId: UUID?, contextFolderPath: String?) {
        if contextId == nil && contextFolderPath == nil {
            entries.removeAll()
            selectedEntryId = nil
        } else {
            entries.removeAll { entry in
                entry.contextId == contextId
                    && (contextFolderPath == nil || entry.contextFolderPath == contextFolderPath)
            }
            if let sid = selectedEntryId,
               !entries.contains(where: { $0.id == sid }) {
                selectedEntryId = nil
            }
        }
        save()
    }

    func setSelectedEntry(id: UUID?) {
        selectedEntryId = id
    }

    func entriesForContext(contextId: UUID?, contextFolderPath: String?) -> [PlanHistoryEntry] {
        entries
            .filter { entry in
                entry.contextId == contextId
                    && (contextFolderPath == nil || entry.contextFolderPath == contextFolderPath)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func markRebuilt(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].rebuildCount += 1
        entries[idx].lastBuildAt = .now
        entries[idx].updatedAt = .now
        save()
    }

    func updateChosenPath(id: UUID, chosenPath: String?) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].chosenPath = chosenPath
        entries[idx].updatedAt = .now
        save()
    }

    func updateSourceMessageId(id: UUID, sourceMessageId: UUID?) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].sourceMessageId = sourceMessageId
        entries[idx].updatedAt = .now
        save()
    }
}
