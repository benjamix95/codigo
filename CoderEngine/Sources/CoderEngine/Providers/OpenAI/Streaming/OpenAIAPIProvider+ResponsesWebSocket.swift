import Foundation

extension OpenAIAPIProvider {
    func attemptResponsesWebSocket(
        includeTools: Bool,
        resolvedContent: Any,
        systemPrompt: String,
        session: URLSession,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws -> (retrySignal: String?, didStart: Bool) {
        guard let wsURL = Self.responsesWebSocketURL(from: baseURL) else {
            throw CoderEngineError.apiError("Invalid WebSocket URL from baseURL: \(baseURL)")
        }

        var request = URLRequest(url: wsURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer {
            socket.cancel(with: URLSessionWebSocketTask.CloseCode.normalClosure, reason: nil)
        }

        var responsePayload: [String: Any] = [
            "model": model,
            "instructions": systemPrompt,
            "input": Self.responseInput(from: resolvedContent),
            "stream": true,
        ]
        if includeTools {
            responsePayload["tools"] = Self.responseToolDefinitions
        }
        if Self.isReasoningModel(model), let effort = reasoningEffort {
            responsePayload["reasoning"] = ["effort": effort]
        }

        let createEvent: [String: Any] = [
            "type": "response.create",
            "response": responsePayload,
        ]

        let encodedCreate = try JSONSerialization.data(withJSONObject: createEvent)
        guard let createText = String(data: encodedCreate, encoding: .utf8) else {
            throw CoderEngineError.apiError("Failed to encode WebSocket request")
        }
        try await socket.send(.string(createText))

        var didEmitUsage = false
        var didStartStream = false
        var toolArgsById: [String: String] = [:]
        var toolNameById: [String: String] = [:]
        var finalizedToolIds = Set<String>()
        var accumulatedReasoning = ""

        while true {
            let message = try await Self.receiveWebSocketMessage(
                socket: socket,
                timeoutSeconds: timeoutSeconds
            )
            let payloadText: String
            switch message {
            case .string(let text):
                payloadText = text
            case .data(let data):
                payloadText = String(data: data, encoding: .utf8) ?? ""
            @unknown default:
                payloadText = ""
            }

            guard !payloadText.isEmpty,
                  let data = payloadText.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            let type = (json["type"] as? String ?? "").lowercased()
            if type == "error" {
                let errorMessage = Self.extractRealtimeErrorMessage(from: json)
                if includeTools && Self.isToolUnsupportedError(errorMessage) {
                    return (errorMessage, didStartStream)
                }
                throw CoderEngineError.apiError(errorMessage)
            }

            if type == "response.created", !didStartStream {
                didStartStream = true
                continuation.yield(.started)
                continue
            }

            switch type {
            case "response.output_text.delta":
                if !didStartStream {
                    didStartStream = true
                    continuation.yield(.started)
                }
                if let delta = json["delta"] as? String, !delta.isEmpty {
                    continuation.yield(.textDelta(delta))
                }
            case "response.reasoning_text.delta",
                 "response.reasoning_summary_text.delta",
                 "response.reasoning.delta":
                if let delta = json["delta"] as? String, !delta.isEmpty {
                    accumulatedReasoning += delta
                    continuation.yield(.raw(
                        type: "reasoning",
                        payload: [
                            "output": String(accumulatedReasoning.prefix(6_000)),
                            "title": "Reasoning",
                            "group_id": "reasoning-stream",
                        ])
                    )
                }
            case "response.function_call_arguments.delta":
                guard let tcId = Self.responseEventToolCallId(from: json) else { break }
                if let name = Self.stringValue(json["name"] ?? json["function_name"]) {
                    toolNameById[tcId] = name
                }
                let fragment = (json["delta"] as? String) ?? ""
                if fragment.isEmpty { break }
                toolArgsById[tcId, default: ""] += fragment
                continuation.yield(.raw(
                    type: "tool_call_suggested",
                    payload: [
                        "id": tcId,
                        "name": toolNameById[tcId] ?? "",
                        "args_fragment": fragment,
                        "args": toolArgsById[tcId] ?? "",
                        "is_partial": "true",
                    ]))
            case "response.function_call_arguments.done":
                guard let tcId = Self.responseEventToolCallId(from: json) else { break }
                if let name = Self.stringValue(json["name"] ?? json["function_name"]) {
                    toolNameById[tcId] = name
                }
                let args = (json["arguments"] as? String) ?? toolArgsById[tcId] ?? ""
                toolArgsById[tcId] = args
                finalizedToolIds.insert(tcId)
                continuation.yield(.raw(
                    type: "tool_call_suggested",
                    payload: [
                        "id": tcId,
                        "name": toolNameById[tcId] ?? "",
                        "args": args,
                        "is_partial": "false",
                    ]))
            case "response.output_item.added", "response.output_item.done":
                guard let item = json["item"] as? [String: Any],
                      (item["type"] as? String)?.lowercased() == "function_call"
                else {
                    break
                }
                let tcId =
                    Self.stringValue(item["id"])
                    ?? Self.stringValue(item["call_id"])
                    ?? Self.responseEventToolCallId(from: json)
                    ?? UUID().uuidString
                if let name = Self.stringValue(item["name"]) {
                    toolNameById[tcId] = name
                }
                if let args = item["arguments"] as? String, !args.isEmpty {
                    toolArgsById[tcId] = args
                }
                if type == "response.output_item.done" {
                    let args = toolArgsById[tcId] ?? ""
                    finalizedToolIds.insert(tcId)
                    continuation.yield(.raw(
                        type: "tool_call_suggested",
                        payload: [
                            "id": tcId,
                            "name": toolNameById[tcId] ?? "",
                            "args": args,
                            "is_partial": "false",
                        ]))
                }
            case "response.completed":
                if let (inp, out) = Self.extractUsageFromResponseEvent(json) {
                    continuation.yield(.raw(
                        type: "usage",
                        payload: [
                            "input_tokens": "\(inp)",
                            "output_tokens": "\(out)",
                            "model": model,
                        ]))
                    didEmitUsage = true
                }

                for (tcId, args) in toolArgsById where !finalizedToolIds.contains(tcId) {
                    continuation.yield(.raw(
                        type: "tool_call_suggested",
                        payload: [
                            "id": tcId,
                            "name": toolNameById[tcId] ?? "",
                            "args": args,
                            "is_partial": "false",
                        ]))
                }

                if !didEmitUsage {
                    continuation.yield(.raw(
                        type: "usage",
                        payload: [
                            "input_tokens": "-1",
                            "output_tokens": "-1",
                            "model": model,
                        ]))
                }
                continuation.yield(.completed)
                continuation.finish()
                return (nil, didStartStream)
            case "response.failed":
                throw CoderEngineError.apiError(Self.extractRealtimeErrorMessage(from: json))
            default:
                continue
            }
        }
    }
}
