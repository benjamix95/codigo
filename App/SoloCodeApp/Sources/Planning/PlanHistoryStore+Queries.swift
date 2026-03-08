import Foundation

extension PlanHistoryStore {
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
            let parentDir = storageURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[PlanHistoryStore] save failed: \(error.localizedDescription)")
            #endif
        }
    }

    func setSelectedEntry(id: UUID?) {
        selectedEntryId = id
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
}
