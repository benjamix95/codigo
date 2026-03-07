import Foundation

extension ToolEnabledLLMProvider {
    func summarizeToolResultEvents(_ events: [StreamEvent], marker: CoderIDEMarker) -> [String: String]? {
        var summary: [String: String] = [
            "id": marker.payload["id"] ?? UUID().uuidString,
            "name": marker.payload["name"] ?? ""
        ]
        var foundCompletion = false
        var sawFailure = false
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_execution_error" || payload["status"] == "failed" {
                summary["status"] = "failed"
                summary["detail"] = payload["detail"] ?? payload["stderr"] ?? "tool failed"
                foundCompletion = true
                sawFailure = true
            } else if !sawFailure, (payload["status"] == "completed" || payload["status"] == "success") {
                // Only accept success if no failure was seen (failure-wins precedence)
                summary["status"] = "completed"
                summary["detail"] = payload["detail"] ?? payload["title"] ?? "ok"
                let toolName = summary["name"] ?? ""
                if shouldIncludeToolOutputInFollowUp(toolName: toolName),
                   let output = payload["output"],
                   !output.isEmpty {
                    summary["output"] = String(output.prefix(8000))
                }
                if let path = payload["path"] ?? payload["file"], !path.isEmpty {
                    summary["path"] = path
                }
                foundCompletion = true
            }
        }
        return foundCompletion ? summary : nil
    }

    func buildFollowUpPrompt(originalPrompt: String, transcript: String, toolResults: [[String: String]]) -> String {
        let resultsSection: String
        if toolResults.isEmpty {
            resultsSection = """
            (No tools used in the previous round.)

            Continue the task autonomously until completion.
            If you need more tools, use tool calls and execute/verify/fix loops as needed.
            Do not stop at a plan or intention statement.
            When finished: you MUST provide a final summary to the user — what changed, which files, outcome, verification.
            """
        } else {
            let formatted = toolResults.map { result in
                let id = result["id"] ?? "-"
                let name = result["name"] ?? "-"
                let status = result["status"] ?? "unknown"
                let detail = result["detail"] ?? ""
                let path = result["path"].map { "\npath: \($0)" } ?? ""
                let output: String
                if shouldIncludeToolOutputInFollowUp(toolName: name) {
                    output = result["output"].map { "\noutput:\n\($0)" } ?? ""
                } else {
                    output = ""
                }
                return "- tool_call id=\(id), name=\(name), status=\(status)\n  detail: \(detail)\(path)\(output)"
            }.joined(separator: "\n")
            resultsSection = """
            Tool results from previous round:
            \(formatted)

            Continue using these results autonomously.
            If you need more tools, use tool calls and keep iterating until done.
            If a check fails, fix and re-check before finalizing.
            When finished: you MUST provide a final summary to the user — what changed, which files, outcome, verification.
            """
        }

        return """
        \(toolProtocolPrompt)

        Original user prompt:
        \(originalPrompt)

        Conversation transcript:
        \(String(transcript.suffix(48_000)))

        \(resultsSection)
        """
    }

    func shouldIncludeToolOutputInFollowUp(toolName: String) -> Bool {
        switch toolName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bash", "command_execution", "shell":
            return false
        default:
            return true
        }
    }

    func parseArgsJSON(_ raw: String) -> [String: String]? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            return nil
        }
        var out: [String: String] = [:]
        for (k, v) in dict {
            if let s = v as? String {
                out[k] = s
            } else if v is NSNull {
                out[k] = "null"
            } else if let b = v as? Bool {
                out[k] = b ? "true" : "false"
            } else if let n = v as? NSNumber {
                out[k] = n.stringValue
            } else if JSONSerialization.isValidJSONObject(v) {
                if let jsonData = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    out[k] = jsonStr
                } else {
                    out[k] = String(describing: v)
                }
            } else {
                out[k] = String(describing: v)
            }
        }
        return out
    }

    func markerDedupeKey(_ marker: CoderIDEMarker) -> String {
        // Use content-based key (excluding unique "id") so that repeated
        // calls with the same tool name + arguments are correctly deduplicated.
        let stablePayload = marker.payload
            .filter { $0.key.lowercased() != "id" }
            .map { key, value in "\(key)=\(value)" }
            .sorted()
            .joined(separator: "|")
        return "\(marker.kind)|\(stablePayload)"
    }


}
