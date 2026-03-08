import Foundation

extension OpenAIAPIProvider {
    static func extractUsage(from json: [String: Any]) -> (Int, Int)? {
        guard let usage = json["usage"] as? [String: Any] else { return nil }
        let input = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int)
        let output = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int)
        guard let input, let output else { return nil }
        return (input, output)
    }

    /// Extract a human-readable error message from an API error JSON body.
    static func extractErrorMessage(from body: String, statusCode: Int) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let snippet = body.prefix(300)
            return "HTTP \(statusCode): \(snippet.isEmpty ? "empty response" : String(snippet))"
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            let errorType = (error["type"] as? String) ?? (error["code"] as? String) ?? ""
            let prefix = errorType.isEmpty ? "" : "[\(errorType)] "
            return "HTTP \(statusCode): \(prefix)\(message)"
        }

        if let message = json["message"] as? String {
            return "HTTP \(statusCode): \(message)"
        }

        return "HTTP \(statusCode): \(String(body.prefix(300)))"
    }

    static func extractUsageFromResponseEvent(_ json: [String: Any]) -> (Int, Int)? {
        if let usage = json["usage"] as? [String: Any] {
            let input = (usage["input_tokens"] as? Int) ?? (usage["prompt_tokens"] as? Int)
            let output = (usage["output_tokens"] as? Int) ?? (usage["completion_tokens"] as? Int)
            if let input, let output {
                return (input, output)
            }
        }

        if let response = json["response"] as? [String: Any],
           let usage = response["usage"] as? [String: Any] {
            let input = (usage["input_tokens"] as? Int) ?? (usage["prompt_tokens"] as? Int)
            let output = (usage["output_tokens"] as? Int) ?? (usage["completion_tokens"] as? Int)
            if let input, let output {
                return (input, output)
            }
        }
        return nil
    }

    static func extractRealtimeErrorMessage(from event: [String: Any]) -> String {
        if let error = event["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if let code = error["code"] as? String, !code.isEmpty {
                return code
            }
        }
        if let message = event["message"] as? String, !message.isEmpty {
            return message
        }
        return "Unknown WebSocket error"
    }

    static func stringValue(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let intValue = value as? Int {
            return String(intValue)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func responseEventToolCallId(from event: [String: Any]) -> String? {
        if let itemId = stringValue(event["item_id"]) { return itemId }
        if let callId = stringValue(event["call_id"]) { return callId }
        if let id = stringValue(event["id"]) { return id }
        if let outputIndex = stringValue(event["output_index"]) {
            return "idx-\(outputIndex)"
        }
        return nil
    }
}
