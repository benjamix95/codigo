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

    @Published private var cache: [TraceKey: [ToolTraceEvent]] = [:]

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

    func startTurn(conversationId: UUID, assistantMessageId: UUID, providerId _: String) {
        let key = TraceKey(conversationId: conversationId, assistantMessageId: assistantMessageId)
        _ = loadIfNeeded(for: key)
        ensureTraceFileExists(for: key)
    }

    func append(event: ToolTraceEvent) {
        let key = TraceKey(conversationId: event.conversationId, assistantMessageId: event.assistantMessageId)
        var events = loadIfNeeded(for: key)
        events.append(event)
        events.sort { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.timestamp < rhs.timestamp
        }
        cache[key] = events
        appendEventToDisk(event, for: key)
    }

    func events(conversationId: UUID, assistantMessageId: UUID) -> [ToolTraceEvent] {
        let key = TraceKey(conversationId: conversationId, assistantMessageId: assistantMessageId)
        return loadIfNeeded(for: key)
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

    func finalizeTurn(conversationId _: UUID, assistantMessageId _: UUID) {
        // Intentionally no-op: traces are persisted incrementally on every append.
    }

    private func loadIfNeeded(for key: TraceKey) -> [ToolTraceEvent] {
        if let cached = cache[key] {
            return cached
        }
        let loaded = loadEventsFromDisk(for: key)
        cache[key] = loaded
        return loaded
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
        out.sort { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.timestamp < rhs.timestamp
        }
        return out
    }

    private func appendEventToDisk(_ event: ToolTraceEvent, for key: TraceKey) {
        ensureTraceFileExists(for: key)
        let url = fileURL(for: key)
        guard let encoded = try? encoder.encode(event) else { return }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer {
            try? handle.close()
        }
        handle.seekToEndOfFile()
        handle.write(encoded)
        handle.write(Data([0x0A]))
    }

    private func ensureTraceFileExists(for key: TraceKey) {
        let url = fileURL(for: key)
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
            .appendingPathComponent("Codigo", isDirectory: true)
            .appendingPathComponent("ToolTrace", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    private func fileURL(for key: TraceKey) -> URL {
        baseDir()
            .appendingPathComponent(key.conversationId.uuidString, isDirectory: true)
            .appendingPathComponent("\(key.assistantMessageId.uuidString).jsonl", isDirectory: false)
    }
}
