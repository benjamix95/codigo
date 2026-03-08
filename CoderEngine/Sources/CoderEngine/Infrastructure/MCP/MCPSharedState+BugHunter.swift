import Foundation

extension MCPSharedState {
    public static var bugHunterDirectoryPath: URL {
        sharedDirectory.appendingPathComponent("bughunter")
    }

    public static var bugHunterSnapshotsDirectoryPath: URL {
        bugHunterDirectoryPath.appendingPathComponent("runs")
    }

    public static var bugHunterCommandsFilePath: URL {
        bugHunterDirectoryPath.appendingPathComponent("commands.json")
    }

    public static var bugHunterHookEventsFilePath: URL {
        bugHunterDirectoryPath.appendingPathComponent("hook-events.json")
    }

    public static func bugHunterRunFilePath(runId: String) -> URL {
        bugHunterSnapshotsDirectoryPath.appendingPathComponent("\(runId).json")
    }

    public static func writeBugHunterSnapshot(_ snapshot: MCPSharedBugHunterSnapshot) {
        withBugHunterFileLock {
            ensureBugHunterDirectories()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: bugHunterRunFilePath(runId: snapshot.runId), options: .atomic)
        }
    }

    public static func readBugHunterSnapshot(runId: String) -> MCPSharedBugHunterSnapshot? {
        withBugHunterFileLock {
            guard let data = try? Data(contentsOf: bugHunterRunFilePath(runId: runId)) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(MCPSharedBugHunterSnapshot.self, from: data)
        }
    }

    public static func readBugHunterSnapshots(
        conversationId: UUID? = nil
    ) -> [MCPSharedBugHunterSnapshot] {
        withBugHunterFileLock {
            ensureBugHunterDirectories()
            let normalizedConversationId = conversationId?.uuidString.lowercased()
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: bugHunterSnapshotsDirectoryPath,
                includingPropertiesForKeys: nil
            ) else {
                return []
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return urls
                .filter { $0.pathExtension == "json" }
                .compactMap { try? Data(contentsOf: $0) }
                .compactMap { try? decoder.decode(MCPSharedBugHunterSnapshot.self, from: $0) }
                .filter { snapshot in
                    guard let normalizedConversationId else { return true }
                    return snapshot.conversationId == normalizedConversationId
                }
                .sorted { lhs, rhs in
                    if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
                        return lhs.lastUpdatedAt > rhs.lastUpdatedAt
                    }
                    return lhs.runId > rhs.runId
                }
        }
    }

    static func ensureBugHunterDirectories() {
        let directories = [sharedDirectory, bugHunterDirectoryPath, bugHunterSnapshotsDirectoryPath]
        for directory in directories where !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
