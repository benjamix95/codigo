import Foundation
import MCP
import os

extension MCPSessionManager {
    /// Convert MCP Value to a JSON-compatible Swift object.
    public func valueToJSONObject(_ value: Value) -> Any {
        switch value {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { valueToJSONObject($0) }
        case .object(let dict):
            return dict.reduce(into: [String: Any]()) { result, kv in
                result[kv.key] = valueToJSONObject(kv.value)
            }
        case .data(_, let data): return data.base64EncodedString()
        @unknown default: return String(describing: value)
        }
    }

    public func flattenContent(_ content: [Tool.Content]) -> String {
        if content.isEmpty { return "(no content)" }
        var chunks: [String] = []
        for item in content {
            switch item {
            case .text(let text):
                if !text.isEmpty { chunks.append(text) }
            case .image(_, let mimeType, _):
                chunks.append("[image \(mimeType)]")
            case .audio(_, let mimeType):
                chunks.append("[audio \(mimeType)]")
            default:
                chunks.append(String(describing: item))
            }
        }
        return chunks.joined(separator: "\n")
    }

    public func parseValue(_ raw: String) -> Value {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .string("") }
        if trimmed == "true" { return .bool(true) }
        if trimmed == "false" { return .bool(false) }
        if trimmed == "null" { return .null }
        if let i = Int(trimmed) { return .int(i) }
        if let d = Double(trimmed), trimmed.contains(".") { return .double(d) }

        if let data = trimmed.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) {
            return toValue(parsed)
        }
        return .string(trimmed)
    }

    public func toValue(_ obj: Any) -> Value {
        switch obj {
        case is NSNull:
            return .null
        case is MCPNullValue:
            return .null
        case let b as Bool:
            return .bool(b)
        case let i as Int:
            return .int(i)
        case let n as NSNumber:
            // NSNumber can be bool/int/double — check type ID first
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            if floor(n.doubleValue) == n.doubleValue {
                return .int(n.intValue)
            }
            return .double(n.doubleValue)
        case let s as String:
            return .string(s)
        case let arr as [Any]:
            return .array(arr.map { toValue($0) })
        case let arr as [any Sendable]:
            return .array(arr.map { toValue($0) })
        case let dict as [String: Any]:
            var mapped: [String: Value] = [:]
            for (k, v) in dict {
                mapped[k] = toValue(v)
            }
            return .object(mapped)
        case let dict as [String: any Sendable]:
            var mapped: [String: Value] = [:]
            for (k, v) in dict {
                mapped[k] = toValue(v)
            }
            return .object(mapped)
        default:
            return .string(String(describing: obj))
        }
    }

    public func classifyMCPError(_ error: Error) -> MCPErrorCategory {
        if let runtimeError = error as? ToolRuntimeError {
            switch runtimeError {
            case .timeout:
                return .timeout
            case .validation:
                return .user
            case .mcpUnavailable:
                return .tool
            case .transport, .sandboxViolation, .budgetExceeded:
                return .transport
            }
        }

        let msg = error.localizedDescription.lowercased()
        if msg.contains("timeout") || msg.contains("timed out") {
            return .timeout
        }
        if msg.contains("invalid params")
            || msg.contains("validation")
            || msg.contains("missing required")
            || msg.contains("bad request")
        {
            return .user
        }
        if msg.contains("tool not found")
            || msg.contains("method not found")
            || msg.contains("unknown tool")
            || msg.contains("unsupported tool")
        {
            return .tool
        }
        if msg.contains("parse error")
            || msg.contains("invalid json")
            || msg.contains("protocol")
        {
            return .protocolViolation
        }
        if msg.contains("broken pipe")
            || msg.contains("connection reset")
            || msg.contains("not connected")
            || msg.contains("transport")
            || msg.contains("econnreset")
        {
            return .transport
        }
        return .unknown
    }

    public func shouldRetry(error: Error, category: MCPErrorCategory, attempt: Int) -> Bool {
        guard attempt < retryPolicy.maxAttempts else { return false }
        switch category {
        case .transport, .timeout, .protocolViolation:
            return true
        case .tool, .user, .unknown:
            return false
        }
    }

    public func backoffBeforeRetry(forAttempt attempt: Int) async throws {
        let index = max(0, attempt - 1)
        let baseDelay = index < retryPolicy.backoffDelaysMs.count
            ? retryPolicy.backoffDelaysMs[index]
            : retryPolicy.backoffDelaysMs.last ?? 0
        let jitter = retryPolicy.jitterMs > 0 ? Int.random(in: 0...retryPolicy.jitterMs) : 0
        let totalDelay = max(0, baseDelay + jitter)
        guard totalDelay > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(totalDelay) * 1_000_000)
    }

    public func normalizeMCPError(
        _ error: Error,
        category: MCPErrorCategory,
        toolName: String,
        timeoutMs: Int
    ) -> Error {
        if let runtimeError = error as? ToolRuntimeError {
            return runtimeError
        }
        switch category {
        case .timeout:
            return ToolRuntimeError.timeout(tool: "mcp:\(toolName)", ms: timeoutMs)
        case .user:
            return ToolRuntimeError.validation(error.localizedDescription)
        case .tool:
            return ToolRuntimeError.mcpUnavailable(error.localizedDescription)
        case .transport, .protocolViolation, .unknown:
            return ToolRuntimeError.transport(error.localizedDescription)
        }
    }

    public func healthForServer(_ cfg: MCPConfigLoader.DetectedServer) async -> String {
        do {
            _ = try await tools(for: cfg)
            return "ok"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    public func resetSession(_ id: String) async throws {
        if let existing = sessions[id] {
            await disposeSession(existing)
            sessions.removeValue(forKey: id)
        }
    }

    func disposeSession(
        _ session: MCPServerSession,
        waitForExit: Bool = false
    ) async {
        var mutableSession = session
        await mutableSession.client.disconnect()
        mutableSession.transportResources.closeAll()
        MCPTransportFactory.terminateProcess(
            mutableSession.process,
            waitForExit: waitForExit
        )
    }
}
