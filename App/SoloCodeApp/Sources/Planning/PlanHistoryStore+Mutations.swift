import Foundation

extension PlanHistoryStore {
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
        selectedEntryIdByConversation[conversationId] = entry.id
        selectedEntryId = entry.id
        save()

        // Also write .md file to .solocode/plan/
        if let folderPath = contextFolderPath {
            let planDir = PlanHistoryStore.solocodePlanDirectory(for: folderPath)
            do {
                try FileManager.default.createDirectory(at: planDir, withIntermediateDirectories: true)
            } catch {
                NSLog("[PlanHistoryStore] createDirectory failed: %@", error.localizedDescription)
            }
            let safeName = sanitizeTitle(safeTitle)
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "_")
            let fileName = safeName.isEmpty ? "plan" : String(safeName.prefix(30))
            let fileURL = planDir.appendingPathComponent("\(fileName).md")
            do {
                try safeMarkdown.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                NSLog("[PlanHistoryStore] write plan file failed: %@", error.localizedDescription)
            }
        }

        return entry
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
        selectedEntryIdByConversation[copy.conversationId] = copy.id
        selectedEntryId = copy.id
        save()
        return copy
    }

    func deleteEntry(id: UUID) {
        let removedConversationIds = entries
            .filter { $0.id == id }
            .map(\.conversationId)
        entries.removeAll { $0.id == id }
        for conversationId in removedConversationIds {
            if selectedEntryIdByConversation[conversationId] == id {
                selectedEntryIdByConversation.removeValue(forKey: conversationId)
            }
        }
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
            selectedEntryIdByConversation.removeAll()
            selectedEntryId = nil
        } else {
            let removedEntries = entries.filter { entry in
                let matchesContext = contextId != nil && entry.contextId == contextId
                let matchesFolder = contextFolderPath != nil && entry.contextFolderPath == contextFolderPath
                return matchesContext || matchesFolder
            }
            entries.removeAll { entry in
                let matchesContext = contextId != nil && entry.contextId == contextId
                let matchesFolder = contextFolderPath != nil && entry.contextFolderPath == contextFolderPath
                return matchesContext || matchesFolder
            }
            for entry in removedEntries where selectedEntryIdByConversation[entry.conversationId] == entry.id {
                selectedEntryIdByConversation.removeValue(forKey: entry.conversationId)
            }
            if let sid = selectedEntryId,
               !entries.contains(where: { $0.id == sid }) {
                selectedEntryId = nil
            }
        }
        save()
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

    /// Update the plan markdown (from manual edit or agent update) and
    /// persist both the history entry AND the `.solocode/plan/` file.
    func updateMarkdown(id: UUID, markdown: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let capped = String(markdown.prefix(configuredMaxMarkdownLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        entries[idx].markdown = capped.isEmpty ? entries[idx].markdown : capped
        entries[idx].updatedAt = .now
        save()
        writePlanFile(entry: entries[idx])
    }

    /// Update the plan title.
    func updateTitle(id: UUID, title: String) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].title = sanitizeTitle(title)
        entries[idx].updatedAt = .now
        save()
        writePlanFile(entry: entries[idx])
    }

    /// Re-write the `.solocode/plan/{name}.md` file for the given entry.
    func writePlanFile(entry: PlanHistoryEntry) {
        guard let folderPath = entry.contextFolderPath else { return }
        let planDir = PlanHistoryStore.solocodePlanDirectory(for: folderPath)
        do {
            try FileManager.default.createDirectory(at: planDir, withIntermediateDirectories: true)
        } catch {
            NSLog("[PlanHistoryStore] createDirectory failed: %@", error.localizedDescription)
        }
        let safeName = sanitizeTitle(entry.title)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let fileName = safeName.isEmpty ? "plan" : String(safeName.prefix(30))
        let fileURL = planDir.appendingPathComponent("\(fileName).md")
        do {
            try entry.markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[PlanHistoryStore] write plan file failed: %@", error.localizedDescription)
        }
    }
}
