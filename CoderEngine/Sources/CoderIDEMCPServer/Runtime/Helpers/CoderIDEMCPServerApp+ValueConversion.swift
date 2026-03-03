import Foundation
import CoderEngine
import MCP

extension CoderIDEMCPServerApp {
    static func valueToString(_ value: Value) -> String {
        switch value {
        case .string(let s):
            return s
        case .int(let i):
            return "\(i)"
        case .double(let d):
            return "\(d)"
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return ""
        default:
            // For arrays/objects, encode as JSON string
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            if let data = try? encoder.encode(value),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "\(value)"
        }
    }

    static func valueToSendable(_ value: Value) -> (any Sendable) {
        switch value {
        case .string(let s):
            return s
        case .int(let i):
            return i
        case .double(let d):
            return d
        case .bool(let b):
            return b
        case .null:
            return MCPNullValue()
        case .array(let items):
            return items.map { valueToSendable($0) }
        case .object(let dict):
            var mapped: [String: any Sendable] = [:]
            for (key, item) in dict {
                mapped[key] = valueToSendable(item)
            }
            return mapped
        default:
            return valueToString(value)
        }
    }
}
