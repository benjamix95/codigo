import Foundation

extension UnifiedToolRuntime {
    static func syntheticIDEStateEventsFromMCP(
        call: ToolCall,
        completedPayload: [String: String]
    ) -> [StreamEvent] {
        let rawTool = firstNonEmptyString(
            in: completedPayload,
            keys: ["mcp_tool", "tool_name"]
        ) ?? firstNonEmptyString(
            in: call.args,
            keys: ["mcp_tool", "tool", "name"]
        ) ?? ""
        let arguments = mergedMCPCallArguments(from: call.args)
        let metadata = syntheticMCPMetadata(
            call: call,
            completedPayload: completedPayload,
            arguments: arguments,
            normalizedTool: IDEStateSyntheticEventFactory.normalizeTool(rawTool)
        )
        let detail = firstNonEmptyString(
            in: completedPayload,
            keys: ["detail", "error", "stderr", "output"]
        )
        let status = metadata["status"] ?? completedPayload["status"]

        return IDEStateSyntheticEventFactory.events(
            rawTool: rawTool,
            arguments: arguments,
            metadata: metadata,
            status: status,
            failureDetail: detail
        ).map { event in
            .raw(type: event.type, payload: event.payload)
        }
    }
}
