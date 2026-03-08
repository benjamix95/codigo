import Foundation

extension ToolEnabledLLMProvider {
    struct ResolvedSubagentInvocation: Sendable, Equatable {
        let toolName: String
        let role: SubagentRole
    }

    static func resolveSubagentInvocation(
        toolName: String,
        payload: [String: String]
    ) -> ResolvedSubagentInvocation? {
        let directCandidates = [
            toolName,
            payload["name"],
            payload["tool"],
            payload["mcp_tool"],
            payload["tool_name"],
        ].compactMap { $0 }

        for candidate in directCandidates {
            if let role = SubagentRole.fromToolName(candidate) {
                return ResolvedSubagentInvocation(
                    toolName: role.toolName,
                    role: role
                )
            }
        }

        let normalized = ProviderToolEventMapper.normalizeToolIdentifier(toolName)
        guard normalized == "mcp" || normalized == "mcp_call" else { return nil }

        let wrappedCandidates = [
            payload["tool"],
            payload["mcp_tool"],
            payload["tool_name"],
            payload["name"],
        ].compactMap { $0 }
        for candidate in wrappedCandidates {
            if let role = SubagentRole.fromToolName(candidate) {
                return ResolvedSubagentInvocation(
                    toolName: role.toolName,
                    role: role
                )
            }
        }

        return nil
    }

    static func adaptedMarkerForResolvedSubagent(
        _ marker: CoderIDEMarker,
        resolved: ResolvedSubagentInvocation
    ) -> CoderIDEMarker {
        var payload = marker.payload
        payload["name"] = resolved.toolName
        payload["tool"] = resolved.toolName
        payload["tool_name"] = resolved.toolName
        payload.removeValue(forKey: "mcp_tool")
        return CoderIDEMarker(kind: marker.kind, payload: payload)
    }
}
