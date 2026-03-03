import Foundation

let planHistoryUserDefaultsKey = "CoderIDE.planHistory"
let planHistoryMaxEntriesPreferenceKey = "plan_history_max_entries"
let planHistoryMaxMarkdownLengthPreferenceKey = "plan_history_max_markdown_chars"
private let defaultPlanHistoryMaxEntries = 200
private let defaultPlanHistoryMaxMarkdownLength = 65_536
private let allowedPlanHistoryMaxEntries = [50, 100, 200]
private let allowedPlanHistoryMaxMarkdownLengths = [32_768, 49_152, 65_536]
let maxPlanOptionsPersisted = 8
private let maxPlanTitleLength = 120

extension PlanHistoryStore {
    var configuredMaxEntries: Int {
        let stored = userDefaults.integer(forKey: planHistoryMaxEntriesPreferenceKey)
        let value = stored == 0 ? defaultPlanHistoryMaxEntries : stored
        return allowedPlanHistoryMaxEntries.contains(value) ? value : defaultPlanHistoryMaxEntries
    }

    var configuredMaxMarkdownLength: Int {
        let stored = userDefaults.integer(forKey: planHistoryMaxMarkdownLengthPreferenceKey)
        let value = stored == 0 ? defaultPlanHistoryMaxMarkdownLength : stored
        return allowedPlanHistoryMaxMarkdownLengths.contains(value)
            ? value
            : defaultPlanHistoryMaxMarkdownLength
    }

    static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("CoderIDE", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("planHistory.json")
    }

    func trimEntriesInMemory() -> Bool {
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

    func sanitizeTitle(_ raw: String) -> String {
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
}
