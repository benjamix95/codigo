import Foundation

/// Parsing degli eventi JSON di Kilo CLI
///
/// Kilo emette eventi line-delimited JSON con i tipi:
/// - `step_start`: inizio di un passo di esecuzione
/// - `text`: blocco di testo (risposta del modello)
/// - `step_finish`: fine del passo con token usage
/// - `tool_start` / `tool_finish`: esecuzione di tool
enum KiloEventParser {
    static func parse(
        json: [String: Any],
        fullContent: inout String,
        defaultModel: String?
    ) -> [StreamEvent] {
        let eventType = json["type"] as? String ?? ""
        var events: [StreamEvent] = []

        switch eventType {
        case "text":
            if let part = json["part"] as? [String: Any],
               let text = part["text"] as? String, !text.isEmpty {
                fullContent += text
                events.append(.textDelta(text))
            }

        case "tool_start":
            if let part = json["part"] as? [String: Any] {
                let name = part["name"] as? String ?? "tool"
                // Extract tool parameters from input dict or string
                var inputPayload: [String: Any] = [:]
                if let inputDict = part["input"] as? [String: Any] {
                    inputPayload = inputDict
                } else if let inputStr = part["input"] as? String {
                    inputPayload["detail"] = inputStr
                }
                if let argsDict = part["args"] as? [String: Any] {
                    for (k, v) in argsDict where inputPayload[k] == nil {
                        inputPayload[k] = v
                    }
                } else if let argsStr = part["args"] as? String, inputPayload["detail"] == nil {
                    inputPayload["detail"] = argsStr
                }
                if let mapped = ProviderToolEventMapper.map(toolName: name, payload: inputPayload) {
                    events.append(.raw(type: mapped.type, payload: mapped.payload))
                } else {
                    let mapped = ProviderToolEventMapper.mapFallback(tool: name, payload: inputPayload)
                    events.append(.raw(type: mapped.type, payload: mapped.payload))
                }
            }

        case "tool_finish":
            if let part = json["part"] as? [String: Any] {
                let output = (part["output"] as? String)
                    ?? (part["result"] as? String)
                    ?? (part["text"] as? String)
                    ?? ""
                if !output.isEmpty {
                    let name = part["name"] as? String ?? "tool"
                    events.append(.raw(type: "command_execution", payload: [
                        "title": name,
                        "output": String(output.prefix(4_000)),
                        "tool": name,
                        "status": "completed",
                    ]))
                }
            }

        case "step_finish":
            if let part = json["part"] as? [String: Any],
               let tokens = part["tokens"] as? [String: Any] {
                let input = intValue(tokens["input"]) ?? 0
                let output = intValue(tokens["output"]) ?? 0
                if input > 0 || output > 0 {
                    let model = defaultModel ?? "kilo"
                    events.append(.raw(type: "usage", payload: [
                        "input_tokens": "\(input)",
                        "output_tokens": "\(output)",
                        "model": model,
                    ]))
                }
            }

        case "error":
            let message = (json["message"] as? String)
                ?? (json["error"] as? String)
                ?? "Unknown Kilo error"
            events.append(.error(message))

        default:
            break
        }

        return events
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }
}
