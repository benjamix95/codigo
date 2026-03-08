import Foundation

enum MonacoBridgePayloadCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func encodeBase64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    static func decodeBase64(_ text: String) -> String? {
        guard let data = Data(base64Encoded: text) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from payload: [String: Any]) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return nil
        }
        return try? decoder.decode(type, from: data)
    }

    static func jsQuoted(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
            var json = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        json.removeFirst()
        json.removeLast()
        return json
    }

    static func responseScript<T: Encodable>(requestId: String, payload: T) -> String? {
        guard
            let data = try? encoder.encode(payload),
            let json = String(data: data, encoding: .utf8)
        else { return nil }
        let encoded = encodeBase64(json)
        return "window.monacoAPI?.resolveRequest(\(jsQuoted(requestId)), \(jsQuoted(encoded)))"
    }
}
