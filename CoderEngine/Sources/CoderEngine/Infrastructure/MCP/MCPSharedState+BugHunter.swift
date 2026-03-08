import Foundation
import OSLog

private let bugHunterLogger = Logger(subsystem: "com.codigo.CoderEngine", category: "BugHunterIO")

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
            let data: Data
            do {
                data = try encoder.encode(snapshot)
            } catch {
                bugHunterLogger.error("Failed to encode BugHunter snapshot \(snapshot.runId): \(error.localizedDescription)")
                return
            }
            do {
                try data.write(to: bugHunterRunFilePath(runId: snapshot.runId), options: .atomic)
            } catch {
                bugHunterLogger.error("Failed to write BugHunter snapshot \(snapshot.runId): \(error.localizedDescription)")
            }
        }
    }

    public static func readBugHunterSnapshot(runId: String) -> MCPSharedBugHunterSnapshot? {
        withBugHunterFileLock {
            let filePath = bugHunterRunFilePath(runId: runId)
            let data: Data
            do {
                data = try Data(contentsOf: filePath)
            } catch {
                if !FileManager.default.fileExists(atPath: filePath.path) {
                    return nil
                }
                bugHunterLogger.error("Failed to read BugHunter snapshot \(runId): \(error.localizedDescription)")
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                return try decoder.decode(MCPSharedBugHunterSnapshot.self, from: data)
            } catch {
                bugHunterLogger.error("Failed to decode BugHunter snapshot \(runId): \(error.localizedDescription)")
                return nil
            }
        }
    }

    public static func readBugHunterSnapshots(
        conversationId: UUID? = nil
    ) -> [MCPSharedBugHunterSnapshot] {
        withBugHunterFileLock {
            ensureBugHunterDirectories()
            let normalizedConversationId = conversationId?.uuidString.lowercased()
            let urls: [URL]
            do {
                urls = try FileManager.default.contentsOfDirectory(
                    at: bugHunterSnapshotsDirectoryPath,
                    includingPropertiesForKeys: nil
                )
            } catch {
                bugHunterLogger.error("Failed to list BugHunter snapshots directory: \(error.localizedDescription)")
                return []
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return urls
                .filter { $0.pathExtension == "json" }
                .compactMap { url -> Data? in
                    do { return try Data(contentsOf: url) }
                    catch {
                        bugHunterLogger.warning("Failed to read snapshot file \(url.lastPathComponent): \(error.localizedDescription)")
                        return nil
                    }
                }
                .compactMap { data -> MCPSharedBugHunterSnapshot? in
                    do { return try decoder.decode(MCPSharedBugHunterSnapshot.self, from: data) }
                    catch {
                        bugHunterLogger.warning("Failed to decode snapshot: \(error.localizedDescription)")
                        return nil
                    }
                }
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
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                bugHunterLogger.error("Failed to create BugHunter directory \(directory.path): \(error.localizedDescription)")
            }
        }
    }
}
