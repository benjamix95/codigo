import Foundation

extension ClaudeCLIProvider {
    static func parseToolUse(from block: [String: Any]) -> (type: String, payload: [String: String])? {
        guard (block["type"] as? String) == "tool_use",
              let name = block["name"] as? String,
              let input = block["input"] as? [String: Any] else { return nil }
        if let mapped = ProviderToolEventMapper.map(toolName: name, payload: input) {
            return mapped
        }

        // Smart fallback: infer event type from payload keys instead of always using command_execution
        let hasPath = firstString(in: input, keys: ["path", "file_path", "file", "target_path"]) != nil
        let hasCommand = firstString(in: input, keys: ["command", "command_line", "cmd"]) != nil
        let hasQuery = firstString(in: input, keys: ["query", "pattern", "search", "needle"]) != nil
        let hasOldString = firstString(in: input, keys: ["old_string", "old_text"]) != nil
        let hasContent = firstString(in: input, keys: ["content", "new_string", "new_text"]) != nil

        // File change tools: have path + old_string/content modifications
        if hasPath && (hasOldString || (hasContent && !hasCommand)) {
            return ProviderToolEventMapper.map(toolName: "edit", payload: input, typeHint: "file_change")
        }
        // Read tools: have path but no modification keys and no command
        if hasPath && !hasCommand && !hasOldString && !hasContent {
            return ProviderToolEventMapper.map(toolName: "read", payload: input)
        }
        // Search tools: have query but no command
        if hasQuery && !hasCommand {
            return ProviderToolEventMapper.map(toolName: "search", payload: input)
        }

        // True fallback: delegate to the shared mapper so all standard
        // fields (command, output, path, etc.) are extracted consistently.
        return ProviderToolEventMapper.mapFallback(tool: name, payload: input)
    }

    static func extractUsagePayload(
        from json: [String: Any],
        defaultModel: String?
    ) -> [String: String]? {
        guard let usage = extractUsageDictionary(from: json) else { return nil }
        let input = intValue(usage["input_tokens"])
            ?? intValue(usage["prompt_tokens"])
            ?? intValue(usage["input_token_count"])
            ?? 0
        let output = intValue(usage["output_tokens"])
            ?? intValue(usage["completion_tokens"])
            ?? intValue(usage["output_token_count"])
            ?? 0
        guard input > 0 || output > 0 else { return nil }

        let model = firstString(in: json, keys: ["model"])
            ?? defaultModel
            ?? "claude"

        return [
            "input_tokens": "\(input)",
            "output_tokens": "\(output)",
            "model": model,
        ]
    }
}
