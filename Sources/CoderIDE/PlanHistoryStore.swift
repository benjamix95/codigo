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

private let planHistoryUserDefaultsKey = "CoderIDE.planHistory"
let planHistoryMaxEntriesPreferenceKey = "plan_history_max_entries"
let planHistoryMaxMarkdownLengthPreferenceKey = "plan_history_max_markdown_chars"
private let defaultPlanHistoryMaxEntries = 200
private let defaultPlanHistoryMaxMarkdownLength = 65_536
private let allowedPlanHistoryMaxEntries = [50, 100, 200]
private let allowedPlanHistoryMaxMarkdownLengths = [32_768, 49_152, 65_536]
private let maxPlanOptionsPersisted = 8
private let maxPlanTitleLength = 120

@MainActor
final class PlanHistoryStore: ObservableObject {
    @Published private(set) var entries: [PlanHistoryEntry] = []
    @Published var selectedEntryId: UUID?
    private var userDefaultsObserver: NSObjectProtocol?
    private let userDefaults: UserDefaults
    private let storageURL: URL

    private static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("CoderIDE", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("planHistory.json")
    }

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
    }

    private var configuredMaxEntries: Int {
        let stored = userDefaults.integer(forKey: planHistoryMaxEntriesPreferenceKey)
        let value = stored == 0 ? defaultPlanHistoryMaxEntries : stored
        return allowedPlanHistoryMaxEntries.contains(value) ? value : defaultPlanHistoryMaxEntries
    }

    private var configuredMaxMarkdownLength: Int {
        let stored = userDefaults.integer(forKey: planHistoryMaxMarkdownLengthPreferenceKey)
        let value = stored == 0 ? defaultPlanHistoryMaxMarkdownLength : stored
        return allowedPlanHistoryMaxMarkdownLengths.contains(value)
            ? value
            : defaultPlanHistoryMaxMarkdownLength
    }

    private func trimEntriesInMemory() -> Bool {
        let maxEntries = configuredMaxEntries
        let maxMarkdownLength = configuredMaxMarkdownLength
        var updated = false

        let sorted = entries.sorted(by: { $0.createdAt > $1.createdAt })
        if sorted.count > maxEntries {
            entries = Array(sorted.prefix(maxEntries))
            updated = true
        } else if sorted != entries {
            entries = sorted
            updated = true
        }

        for idx in entries.indices {
            let sanitizedMarkdown = String(entries[idx].markdown.prefix(maxMarkdownLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let safeMarkdown = sanitizedMarkdown.isEmpty
                ? "Plan unavailable (empty content)."
                : sanitizedMarkdown
            if entries[idx].markdown != safeMarkdown {
                entries[idx].markdown = safeMarkdown
                entries[idx].updatedAt = .now
                updated = true
            }
        }

        if let sid = selectedEntryId, !entries.contains(where: { $0.id == sid }) {
            selectedEntryId = nil
            updated = true
        }
        return updated
    }

    func applyConfiguredLimits() {
        if trimEntriesInMemory() {
            save()
        }
    }

    func load() {
        // Try file-based storage first, then fall back to UserDefaults for migration.
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([PlanHistoryEntry].self, from: data) {
            entries = decoded.sorted(by: { $0.createdAt > $1.createdAt })
            _ = trimEntriesInMemory()
            return
        }
        // Migrate from UserDefaults if present.
        if let data = userDefaults.data(forKey: planHistoryUserDefaultsKey),
           let decoded = try? JSONDecoder().decode([PlanHistoryEntry].self, from: data) {
            entries = decoded.sorted(by: { $0.createdAt > $1.createdAt })
            _ = trimEntriesInMemory()
            save()
            if FileManager.default.fileExists(atPath: storageURL.path) {
                userDefaults.removeObject(forKey: planHistoryUserDefaultsKey)
            }
            return
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[PlanHistoryStore] save failed: \(error.localizedDescription)")
        }
    }

    private func sanitizeTitle(_ raw: String) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Plan"
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
        let sanitizedMarkdown = String(markdown.prefix(configuredMaxMarkdownLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cappedOptions = Array(options.prefix(maxPlanOptionsPersisted))
        let safeTitle = sanitizeTitle(title)
        let safeMarkdown = sanitizedMarkdown.isEmpty
            ? "Plan unavailable (empty content)."
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
        _ = trimEntriesInMemory()
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

    func findLatestEntry(for conversationId: UUID) -> PlanHistoryEntry? {
        entries
            .filter { $0.conversationId == conversationId }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    @discardableResult
    func duplicateEntry(id: UUID) -> PlanHistoryEntry? {
        guard var copy = findEntry(id: id) else { return nil }
        copy.id = UUID()
        copy.createdAt = .now
        copy.updatedAt = .now
        copy.sourceMessageId = nil
        entries.append(copy)
        _ = trimEntriesInMemory()
        selectedEntryId = copy.id
        save()
        return copy
    }

    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        if selectedEntryId == id { selectedEntryId = nil }
        save()
    }

    /// Deletes all planning entries for the specified context (or all if nil).
    /// Uses OR matching: an entry is removed if it matches by contextId OR by
    /// contextFolderPath, so entries created before one of the fields was
    /// populated are not missed.
    func deleteAllForContext(contextId: UUID?, contextFolderPath: String?) {
        if contextId == nil && contextFolderPath == nil {
            entries.removeAll()
            selectedEntryId = nil
        } else {
            entries.removeAll { entry in
                let matchesContext = contextId != nil && entry.contextId == contextId
                let matchesFolder = contextFolderPath != nil && entry.contextFolderPath == contextFolderPath
                return matchesContext || matchesFolder
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
        guard contextId != nil || contextFolderPath != nil else {
            return entries.sorted { $0.createdAt > $1.createdAt }
        }
        return entries
            .filter { entry in
                let matchesContext = contextId != nil && entry.contextId == contextId
                let matchesFolder = contextFolderPath != nil && entry.contextFolderPath == contextFolderPath
                return matchesContext || matchesFolder
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
