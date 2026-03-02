import Foundation
import Combine
import CoderEngine

public final class TerminalSession: Identifiable, ObservableObject {
    public let id: UUID
    @Published public var label: String
    @Published public var isAgentOwned: Bool
    @Published public var workingDirectory: String?
    @Published public var isRunning: Bool

    private let bufferLimit = 64_000
    private var _outputBuffer: String = ""
    private let lock = NSLock()

    public init(
        id: UUID = UUID(),
        label: String = "Shell",
        isAgentOwned: Bool = false,
        workingDirectory: String? = nil
    ) {
        self.id = id
        self.label = label
        self.isAgentOwned = isAgentOwned
        self.workingDirectory = workingDirectory
        self.isRunning = true
    }

    public func appendOutput(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        _outputBuffer.append(text)
        if _outputBuffer.count > bufferLimit {
            let drop = _outputBuffer.count - bufferLimit
            _outputBuffer = String(_outputBuffer.dropFirst(drop))
        }
    }

    public func readOutput(lastN: Int = 8_000) -> String {
        lock.lock()
        defer { lock.unlock() }
        if _outputBuffer.count <= lastN { return _outputBuffer }
        return String(_outputBuffer.suffix(lastN))
    }

    public func clearOutput() {
        lock.lock()
        defer { lock.unlock() }
        _outputBuffer = ""
    }

    public var outputLength: Int {
        lock.lock()
        defer { lock.unlock() }
        return _outputBuffer.count
    }
}

@MainActor
public final class TerminalSessionStore: ObservableObject {
    @Published public var sessions: [TerminalSession] = []
    @Published public var activeSessionId: UUID?

    public var activeSession: TerminalSession? {
        guard let id = activeSessionId else { return sessions.first }
        return sessions.first(where: { $0.id == id }) ?? sessions.first
    }

    public init() {}

    @discardableResult
    public func createSession(
        label: String = "Shell",
        cwd: String? = nil,
        isAgent: Bool = false
    ) -> TerminalSession {
        let session = TerminalSession(
            label: label,
            isAgentOwned: isAgent,
            workingDirectory: cwd
        )
        sessions.append(session)
        if activeSessionId == nil || isAgent {
            activeSessionId = session.id
        }
        return session
    }

    public func closeSession(id: UUID) {
        sessions.removeAll(where: { $0.id == id })
        if activeSessionId == id {
            activeSessionId = sessions.first?.id
        }
    }

    public func session(for id: UUID) -> TerminalSession? {
        sessions.first(where: { $0.id == id })
    }

    public func appendOutput(sessionId: UUID, text: String) {
        session(for: sessionId)?.appendOutput(text)
    }

    public func readOutput(sessionId: UUID? = nil, lastN: Int = 8_000) -> String {
        let target: TerminalSession?
        if let sid = sessionId {
            target = session(for: sid)
        } else {
            target = activeSession
        }
        return target?.readOutput(lastN: lastN) ?? ""
    }

    public func readAllSessionsSummary(lastN: Int = 2_000) -> String {
        if sessions.isEmpty { return "(no terminal sessions)" }
        var parts: [String] = []
        for s in sessions {
            let owner = s.isAgentOwned ? "agent" : "user"
            let output = s.readOutput(lastN: lastN)
            let truncated = output.isEmpty ? "(empty)" : output
            parts.append("[\(s.label) (\(owner))] cwd: \(s.workingDirectory ?? "~")\n\(truncated)")
        }
        return parts.joined(separator: "\n---\n")
    }

    public func ensureDefaultSession(cwd: String?) {
        guard sessions.isEmpty else { return }
        createSession(label: "Shell", cwd: cwd, isAgent: false)
    }
}

// MARK: - TerminalBridge conformance

extension TerminalSessionStore: TerminalBridge {
    public func executeInTerminal(command: String, cwd: String?, label: String) async -> (output: String, exitCode: Int32) {
        let session = createSession(label: label, cwd: cwd, isAgent: true)
        let sessionId = session.id

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendOutput(sessionId: sessionId, text: text)
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            appendOutput(sessionId: sessionId, text: "\n[Error: \(error.localizedDescription)]\n")
            return (output: readOutput(sessionId: sessionId, lastN: 16_000), exitCode: 1)
        }

        pipe.fileHandleForReading.readabilityHandler = nil

        await MainActor.run {
            session.isRunning = false
        }

        let output = readOutput(sessionId: sessionId, lastN: 16_000)
        return (output: output, exitCode: process.terminationStatus)
    }

    public func readTerminalOutput(sessionId: String?, lastN: Int) -> String {
        if let idStr = sessionId, let uuid = UUID(uuidString: idStr) {
            return readOutput(sessionId: uuid, lastN: lastN)
        }
        return readOutput(sessionId: nil, lastN: lastN)
    }

    public func allSessionsSummary(lastN: Int) -> String {
        readAllSessionsSummary(lastN: lastN)
    }
}
