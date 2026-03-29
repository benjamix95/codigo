import Foundation
import SwiftUI

struct ToolTraceEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var sequence: Int
    var timestamp: Date
    var providerId: String
    var conversationId: UUID
    var assistantMessageId: UUID
    var type: String
    var title: String
    var detail: String?
    var payload: [String: String]
    var phase: ActivityPhase
    var isRunning: Bool
    var groupId: String?
    var rawKind: String

    init(
        id: UUID = UUID(),
        sequence: Int,
        timestamp: Date,
        providerId: String,
        conversationId: UUID,
        assistantMessageId: UUID,
        type: String,
        title: String,
        detail: String?,
        payload: [String: String],
        phase: ActivityPhase,
        isRunning: Bool,
        groupId: String?,
        rawKind: String
    ) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.providerId = providerId
        self.conversationId = conversationId
        self.assistantMessageId = assistantMessageId
        self.type = type
        self.title = title
        self.detail = detail
        self.payload = payload
        self.phase = phase
        self.isRunning = isRunning
        self.groupId = groupId
        self.rawKind = rawKind
    }
}

struct ToolTraceBindingTarget: Equatable {
    let conversationId: UUID
    let assistantMessageId: UUID
}

struct ToolTraceConversationFileChangeSummary {
    let linesAdded: Int
    let linesRemoved: Int
    let fileCount: Int

    static let empty = ToolTraceConversationFileChangeSummary(
        linesAdded: 0,
        linesRemoved: 0,
        fileCount: 0
    )
}

enum ToolTraceBindingResolver {
    static func resolve(
        activeTurn: ToolTraceBindingTarget?,
        requestedConversationId: UUID?,
        fallbackAssistantMessageId: UUID?
    ) -> ToolTraceBindingTarget? {
        if let activeTurn,
           activeTurn.conversationId == requestedConversationId {
            return activeTurn
        }
        guard let requestedConversationId,
              let fallbackAssistantMessageId else {
            return nil
        }
        return ToolTraceBindingTarget(
            conversationId: requestedConversationId,
            assistantMessageId: fallbackAssistantMessageId
        )
    }
}

@MainActor
final class ToolTraceStore: ObservableObject {
    private struct TraceKey: Hashable {
        let conversationId: UUID
        let assistantMessageId: UUID
    }

    /// In-memory cache of trace events per (conversation, assistant-message) pair.
    /// Mutations that represent *new data* (e.g. `append`) must manually call
    /// `objectWillChange.send()` so SwiftUI picks up the change.
    /// Lazy-loading from disk does NOT send change notifications, avoiding the
    /// "Publishing changes from within view updates" runtime warning.
    private var cache: [TraceKey: [ToolTraceEvent]] = [:]
    private var allEventsCacheByConversation: [UUID: [ToolTraceEvent]] = [:]
    private var fileChangeSummaryCacheByConversation: [UUID: ToolTraceConversationFileChangeSummary] = [:]

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Background queue for all disk I/O — keeps FileHandle operations off the main thread.
    static let diskQueue = DispatchQueue(label: "com.solocode.tooltrace.disk", qos: .utility)

    /// Throttle objectWillChange to avoid flooding SwiftUI with re-renders
    /// during rapid streaming. Coalesces updates within 150ms windows.
    private var changeThrottleTask: DispatchWorkItem?
    private var lastChangeNotification: Date = .distantPast

    private func throttledNotify() {
        let now = Date()
        if now.timeIntervalSince(lastChangeNotification) > 0.15 {
            // Enough time has passed — notify immediately and reset the window.
            // Previously this called throttledNotify() recursively, which
            // wasted a stack frame and re-entered the delayed branch, effectively
            // scheduling a redundant 150ms delayed notification on top of the
            // immediate one.
            lastChangeNotification = now
            changeThrottleTask?.cancel()
            changeThrottleTask = nil
            objectWillChange.send()
            return
        }
        // Within throttle window — coalesce into a single delayed notification.
        changeThrottleTask?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.lastChangeNotification = Date()
            self?.objectWillChange.send()
        }
        changeThrottleTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Blocks until all pending disk writes have completed. For test use.
    func flushDiskWrites() {
        Self.diskQueue.sync {
            Self.flushAllBufferedDiskAppends()
        }
    }

    func startTurn(conversationId: UUID, assistantMessageId: UUID, providerId _: String) {
        let key = TraceKey(conversationId: conversationId, assistantMessageId: assistantMessageId)
        _ = loadIfNeeded(for: key)
        let url = fileURL(for: key)
        Self.diskQueue.async {
            Self.ensureTraceFileExistsOnDisk(at: url)
        }
    }

    func append(event: ToolTraceEvent) {
        let key = TraceKey(conversationId: event.conversationId, assistantMessageId: event.assistantMessageId)
        var events = loadIfNeeded(for: key)
        let canAppendInOrder = events.last.map { last in
            if last.sequence != event.sequence {
                return last.sequence <= event.sequence
            }
            return last.timestamp <= event.timestamp
        } ?? true
        if canAppendInOrder {
            events.append(event)
        } else {
            events.append(event)
            events.sort { lhs, rhs in
                if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
                return lhs.timestamp < rhs.timestamp
            }
        }
        throttledNotify()
        cache[key] = events
        invalidateConversationCaches(conversationId: event.conversationId)
        // Encode on main thread (fast), batch the disk append off the main thread.
        if let encoded = try? encoder.encode(event) {
            let url = fileURL(for: key)
            Self.queueBufferedDiskAppend(encoded, url: url)
        }
    }

    func events(conversationId: UUID, assistantMessageId: UUID) -> [ToolTraceEvent] {
        let key = TraceKey(conversationId: conversationId, assistantMessageId: assistantMessageId)
        return loadIfNeeded(for: key)
    }

    func allEvents(conversationId: UUID) -> [ToolTraceEvent] {
        if let cached = allEventsCacheByConversation[conversationId] {
            return cached
        }
        let events = cache.filter { $0.key.conversationId == conversationId }
            .flatMap(\.value)
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.sequence < rhs.sequence
            }
        allEventsCacheByConversation[conversationId] = events
        return events
    }

    func conversationFileChangeSummary(conversationId: UUID) -> ToolTraceConversationFileChangeSummary {
        if let cached = fileChangeSummaryCacheByConversation[conversationId] {
            return cached
        }
        let allEvents = allEvents(conversationId: conversationId)
        guard !allEvents.isEmpty else {
            fileChangeSummaryCacheByConversation[conversationId] = .empty
            return .empty
        }
        let fileChanges = ToolTraceFileChangeMapper.collect(from: allEvents)
        let summary = ToolTraceConversationFileChangeSummary(
            linesAdded: fileChanges.reduce(0) { $0 + max(0, $1.added) },
            linesRemoved: fileChanges.reduce(0) { $0 + max(0, $1.removed) },
            fileCount: fileChanges.count
        )
        fileChangeSummaryCacheByConversation[conversationId] = summary
        return summary
    }

    func hasTrace(conversationId: UUID, assistantMessageId: UUID) -> Bool {
        let key = TraceKey(conversationId: conversationId, assistantMessageId: assistantMessageId)
        if let cached = cache[key] {
            return !cached.isEmpty
        }
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = attrs?[.size] as? NSNumber
        return (bytes?.intValue ?? 0) > 0
    }

    /// Merge additional payload keys into the most recent event whose `payload["id"]`
    /// matches the given `toolUseId`. Used to attach tool results (linesAdded, output, etc.)
    /// to the card created by the initial tool_use event.
    func mergeResultIntoLastEvent(
        toolUseId: String,
        conversationId: UUID,
        assistantMessageId: UUID,
        resultPayload: [String: String]
    ) {
        let key = TraceKey(conversationId: conversationId, assistantMessageId: assistantMessageId)
        var events = loadIfNeeded(for: key)
        guard let idx = events.lastIndex(where: { $0.payload["id"] == toolUseId }) else { return }
        // Result fields that should always overwrite the tool_use input values.
        let alwaysOverwrite: Set<String> = [
            "linesAdded", "linesRemoved", "additions", "deletions",
            "output", "detail", "status", "stderr",
        ]
        for (k, v) in resultPayload {
            if alwaysOverwrite.contains(k) {
                events[idx].payload[k] = v
            } else if events[idx].payload[k] == nil || events[idx].payload[k]?.isEmpty == true {
                events[idx].payload[k] = v
            }
        }
        events[idx].isRunning = false
        throttledNotify()
        cache[key] = events
        invalidateConversationCaches(conversationId: conversationId)
    }

    func finalizeTurn(conversationId _: UUID, assistantMessageId _: UUID) {
        // Intentionally no-op: traces are persisted incrementally on every append.
    }

    private func loadIfNeeded(for key: TraceKey) -> [ToolTraceEvent] {
        if let cached = cache[key] {
            return cached
        }
        let loaded = loadEventsFromDisk(for: key)
        cache[key] = loaded
        invalidateConversationCaches(conversationId: key.conversationId)
        return loaded
    }

    private func invalidateConversationCaches(conversationId: UUID) {
        allEventsCacheByConversation.removeValue(forKey: conversationId)
        fileChangeSummaryCacheByConversation.removeValue(forKey: conversationId)
    }

    private func loadEventsFromDisk(for key: TraceKey) -> [ToolTraceEvent] {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        guard let content = String(data: data, encoding: .utf8) else { return [] }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        var out: [ToolTraceEvent] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let event = try? decoder.decode(ToolTraceEvent.self, from: lineData) else { continue }
            out.append(event)
        }
        out = settledLoadedEventsForColdStart(out)
        out.sort { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.timestamp < rhs.timestamp
        }
        return out
    }

    /// Ensures the trace file and parent directories exist. Runs on `diskQueue`.
    nonisolated static func ensureTraceFileExistsOnDisk(at url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    private func baseDir() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Solo Code", isDirectory: true)
            .appendingPathComponent("ToolTrace", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    private func fileURL(for key: TraceKey) -> URL {
        baseDir()
            .appendingPathComponent(key.conversationId.uuidString, isDirectory: true)
            .appendingPathComponent("\(key.assistantMessageId.uuidString).jsonl", isDirectory: false)
    }
}
