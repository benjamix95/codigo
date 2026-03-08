import Foundation
import OSLog

private let bugHunterHookEventsLogger = Logger(subsystem: "com.codigo.CoderEngine", category: "BugHunterHookEventsIO")

extension MCPSharedState {
    public static func enqueueBugHunterHookEvent(
        gitRoot: String,
        headSHA: String
    ) {
        withBugHunterFileLock {
            ensureBugHunterDirectories()
            var events = readBugHunterHookEventsUnsafe()
            let normalizedRoot = gitRoot.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedSHA = headSHA.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedRoot.isEmpty, !normalizedSHA.isEmpty else { return }
            if events.contains(where: { $0.gitRoot == normalizedRoot && $0.headSHA == normalizedSHA }) {
                return
            }
            events.append(
                MCPSharedBugHunterHookEvent(
                    id: UUID().uuidString.lowercased(),
                    gitRoot: normalizedRoot,
                    headSHA: normalizedSHA,
                    createdAt: Date()
                )
            )
            writeBugHunterHookEventsUnsafe(events)
        }
    }

    public static func claimBugHunterHookEvents() -> [MCPSharedBugHunterHookEvent] {
        withBugHunterFileLock {
            let events = readBugHunterHookEventsUnsafe()
            writeBugHunterHookEventsUnsafe([])
            return events.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id < $1.id
            }
        }
    }

    private static func readBugHunterHookEventsUnsafe() -> [MCPSharedBugHunterHookEvent] {
        let data: Data
        do {
            data = try Data(contentsOf: bugHunterHookEventsFilePath)
        } catch {
            if !FileManager.default.fileExists(atPath: bugHunterHookEventsFilePath.path) {
                return []
            }
            bugHunterHookEventsLogger.error("Failed to read BugHunter hook events file: \(error.localizedDescription)")
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([MCPSharedBugHunterHookEvent].self, from: data)
        } catch {
            bugHunterHookEventsLogger.warning("JSON decode failed for hook events, trying legacy format: \(error.localizedDescription)")
        }
        guard let raw = String(data: data, encoding: .utf8) else {
            bugHunterHookEventsLogger.error("Failed to read BugHunter hook events as UTF-8 string")
            return []
        }
        return raw
            .components(separatedBy: .newlines)
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3 else { return nil }
                let createdAt = TimeInterval(parts[0]).map(Date.init(timeIntervalSince1970:)) ?? Date()
                return MCPSharedBugHunterHookEvent(
                    id: UUID().uuidString.lowercased(),
                    gitRoot: parts[1],
                    headSHA: parts[2],
                    createdAt: createdAt
                )
            }
    }

    private static func writeBugHunterHookEventsUnsafe(_ events: [MCPSharedBugHunterHookEvent]) {
        ensureBugHunterDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(events)
        } catch {
            bugHunterHookEventsLogger.error("Failed to encode BugHunter hook events: \(error.localizedDescription)")
            return
        }
        do {
            try data.write(to: bugHunterHookEventsFilePath, options: .atomic)
        } catch {
            bugHunterHookEventsLogger.error("Failed to write BugHunter hook events: \(error.localizedDescription)")
        }
    }
}
