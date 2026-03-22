import Foundation

extension CodexCLIProvider {
    static func finalizeAssistantTurnIfNeeded(
        state: inout CodexStreamParserState
    ) -> [StreamEvent] {
        guard !state.turn.lastValidAgentMessage.isEmpty else { return [] }

        var events: [StreamEvent] = []
        emitMarkerEvents(from: state.turn.lastValidAgentMessage, state: &state, events: &events)
        var cleanupCarry = ""
        let cleaned = scrubTechnicalTextChunk(state.turn.lastValidAgentMessage, carry: &cleanupCarry)
        let trimmedCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCleaned.isEmpty {
            let previouslyVisibleText = state.cumulativeVisibleText
            state.turn.emittedAnyAssistantDelta = true
            state.cumulativeVisibleText = trimmedCleaned
            if state.turn.emittedAnyAssistantDelta && !previouslyVisibleText.isEmpty && previouslyVisibleText != trimmedCleaned {
                events.append(.textReplace(trimmedCleaned))
            } else {
                events.append(.textDelta(trimmedCleaned))
            }
        }
        return events
    }

    static func emitMarkerEvents(
        from text: String,
        state: inout CodexStreamParserState,
        events: inout [StreamEvent]
    ) {
        // Marker parsing removed — IDE state tools now go exclusively through MCP.
        // This function is kept as a no-op to preserve the call-site structure;
        // it will be removed in the cleanup phase.
    }

    static func appendRawEvent(
        type: String,
        payload: [String: String],
        state: inout CodexStreamParserState,
        events: inout [StreamEvent]
    ) {
        let key = rawDedupKey(type: type, payload: payload)
        guard state.emittedRawKeys.insert(key).inserted else { return }
        events.append(.raw(type: type, payload: payload))
    }

    static func rawDedupKey(type: String, payload: [String: String]) -> String {
        if type == "reasoning" {
            let group = payload["group_id"] ?? ""
            let preview = String((payload["output"] ?? "").suffix(160))
            return "\(type)|\(group)|\(preview)"
        }
        let identityKeys = [
            "id", "group_id", "queryId", "query_id",
            "tool_call_id", "call_id", "swarm_id", "step_id"
        ]
        let identityKeySet = Set(identityKeys)
        let identifier = identityKeys.compactMap { payload[$0] }.first(where: { !$0.isEmpty }) ?? ""
        let status = (payload["status"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !identifier.isEmpty || !status.isEmpty {
            let fingerprint = payloadFingerprint(
                payload,
                excluding: identityKeySet.union(["status"])
            )
            if !fingerprint.isEmpty {
                return "\(type)|\(identifier)|\(status)|\(fingerprint)"
            }
            return "\(type)|\(identifier)|\(status)"
        }
        let canonicalPayload = payload.keys.sorted().map { key in
            "\(key)=\(payload[key] ?? "")"
        }.joined(separator: "|")
        return "\(type)|\(canonicalPayload)"
    }

    static func payloadFingerprint(_ payload: [String: String], excluding ignored: Set<String>) -> String {
        var hasher = Hasher()
        var didHashAnyEntry = false
        for key in payload.keys.sorted() {
            guard !ignored.contains(key) else { continue }
            let value = payload[key] ?? ""
            didHashAnyEntry = true
            hasher.combine(key)
            hasher.combine(value.count)
            hasher.combine(String(value.prefix(256)))
            hasher.combine(String(value.suffix(256)))
        }
        guard didHashAnyEntry else { return "" }
        return String(hasher.finalize(), radix: 16)
    }

    static func extractAgentMessageChunk(from json: [String: Any]) -> (text: String, isDelta: Bool)? {
        let eventType = (json["type"] as? String) ?? ""
        let finalLikeItemTypes: Set<String> = ["assistant_message", "agent_message", "final_answer", "message", "text"]
        let finalLikeEventTypes: Set<String> = ["assistant_message", "agent_message", "final_answer", "message", "text"]

        if eventType.hasPrefix("item."),
           let item = json["item"] as? [String: Any],
           let itemType = item["type"] as? String,
           finalLikeItemTypes.contains(itemType) {
            if let delta = firstString(in: item, keys: ["delta", "text_delta"]), !delta.isEmpty {
                return (delta, true)
            }
            if let text = extractTextPayload(from: item), !text.isEmpty {
                return (text, false)
            }
            return nil
        }

        if finalLikeEventTypes.contains(eventType) {
            if let text = extractTextPayload(from: json), !text.isEmpty {
                return (text, false)
            }
        }

        return nil
    }

    static func extractAssistantUpdatePayload(from json: [String: Any]) -> [String: String]? {
        let eventType = (json["type"] as? String) ?? ""
        let item = (json["item"] as? [String: Any]) ?? json
        let itemType = (item["type"] as? String) ?? eventType
        guard itemType == "agent_message" || eventType == "agent_message" else {
            return nil
        }
        guard let rawText = extractTextPayload(from: item) ?? extractTextPayload(from: json) else {
            return nil
        }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var payload: [String: String] = [
            "title": "Working",
            "detail": String(
                trimmed
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .prefix(240)
            ),
            "output": String(rawText.prefix(6_000)),
            "status": "in_progress",
        ]
        if let itemId = firstString(in: item, keys: ["id"]), !itemId.isEmpty {
            payload["id"] = itemId
            payload["group_id"] = itemId
        }
        return payload
    }

    static func captureAssistantUpdateState(
        from json: [String: Any],
        state: inout CodexStreamParserState
    ) {
        let eventType = (json["type"] as? String) ?? ""
        let item = (json["item"] as? [String: Any]) ?? json
        let itemType = (item["type"] as? String) ?? eventType
        guard itemType == "agent_message" || eventType == "agent_message" else {
            return
        }

        if let delta = firstString(in: item, keys: ["delta", "text_delta"]), !delta.isEmpty {
            state.turn.lastObservedAgentText += delta
            state.turn.lastValidAgentMessage = state.turn.lastObservedAgentText
            return
        }

        if let text = extractTextPayload(from: item) ?? extractTextPayload(from: json),
           !text.isEmpty {
            state.turn.lastObservedAgentText = text
            state.turn.lastValidAgentMessage = text
        }
    }

    static func extractTextPayload(from obj: Any) -> String? {
        if let s = obj as? String {
            return s
        }
        if let dict = obj as? [String: Any] {
            if let text = dict["text"] as? String { return text }
            if let output = dict["output"] as? String { return output }
            if let message = dict["message"] {
                if let extracted = extractTextPayload(from: message), !extracted.isEmpty {
                    return extracted
                }
            }
            if let item = dict["item"] {
                if let extracted = extractTextPayload(from: item), !extracted.isEmpty {
                    return extracted
                }
            }
            if let event = dict["event"] {
                if let extracted = extractTextPayload(from: event), !extracted.isEmpty {
                    return extracted
                }
            }
            if let content = dict["content"] as? [Any] {
                let chunks = content.compactMap { extractTextPayload(from: $0) }
                if !chunks.isEmpty {
                    return chunks.joined()
                }
            }
            if let output = dict["output"] as? [Any] {
                let chunks = output.compactMap { extractTextPayload(from: $0) }
                if !chunks.isEmpty {
                    return chunks.joined()
                }
            }
            return nil
        }
        if let array = obj as? [Any] {
            let chunks = array.compactMap { extractTextPayload(from: $0) }
            if !chunks.isEmpty {
                return chunks.joined()
            }
        }
        return nil
    }
}
