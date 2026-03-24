import Foundation

// MARK: - Top-Level SSE Event

/// Modello Codable per gli eventi SSE della Anthropic Messages API.
struct AnthropicSSEEvent: Decodable {
    let type: String
    let index: Int?
    let contentBlock: AnthropicContentBlock?
    let delta: AnthropicDelta?
    let usage: AnthropicUsage?
    let error: AnthropicErrorPayload?

    enum CodingKeys: String, CodingKey {
        case type, index, delta, usage, error
        case contentBlock = "content_block"
    }
}

// MARK: - Content Block

struct AnthropicContentBlock: Decodable {
    let type: String
    let id: String?
    let name: String?
    let input: AnyCodableValue?
}

// MARK: - Delta

struct AnthropicDelta: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
    let partialJson: String?

    enum CodingKeys: String, CodingKey {
        case type, text, thinking
        case partialJson = "partial_json"
    }
}

// MARK: - Usage

struct AnthropicUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Error

struct AnthropicErrorPayload: Decodable {
    let type: String?
    let message: String?
}

// MARK: - Message Delta (top-level usage in message_delta events)

struct AnthropicMessageDeltaEvent: Decodable {
    let type: String
    let usage: AnthropicUsage?
}

// MARK: - AnyCodableValue (per campo `input` opzionale)

/// Wrapper type-erased per decodificare valori JSON arbitrari.
enum AnyCodableValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    /// Serializza il valore in JSON string per il campo args dei tool.
    func toJSONString() -> String? {
        switch self {
        case .null:
            return nil
        case .string(let s):
            return s
        case .int, .double, .bool, .dictionary, .array:
            guard let data = try? JSONSerialization.data(
                withJSONObject: toFoundation(),
                options: [.fragmentsAllowed]
            ) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    private func toFoundation() -> Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .dictionary(let dict):
            return dict.mapValues { $0.toFoundation() }
        case .array(let arr):
            return arr.map { $0.toFoundation() }
        }
    }
}
