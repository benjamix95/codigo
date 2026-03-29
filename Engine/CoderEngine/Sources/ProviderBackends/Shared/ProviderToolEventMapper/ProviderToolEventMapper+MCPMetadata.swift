import Foundation

extension ProviderToolEventMapper {
    static func annotateNativeMCPMetadataIfNeeded(
        mapped: (type: String, payload: [String: String]),
        rawToolName: String,
        payload: [String: Any]
    ) -> (type: String, payload: [String: String]) {
        guard let mcpTool = nativeMCPToolName(rawToolName: rawToolName, payload: payload) else {
            return mapped
        }

        var updatedPayload = mapped.payload
        updatedPayload["is_mcp"] = "true"
        updatedPayload["mcp_tool"] = mcpTool

        if let server = firstString(in: payload, keys: ["mcp_server", "server_id", "server"]),
           !server.isEmpty
        {
            updatedPayload["mcp_server"] = server
            updatedPayload["server_id"] = server
        } else if updatedPayload["mcp_server"]?.isEmpty != false {
            updatedPayload["mcp_server"] = "coderide"
            updatedPayload["server_id"] = "coderide"
        }

        return (mapped.type, updatedPayload)
    }

    private static func nativeMCPToolName(
        rawToolName: String,
        payload: [String: Any]
    ) -> String? {
        let explicitCandidates = [
            firstString(in: payload, keys: ["mcp_tool", "tool_name"]),
            rawToolName,
            firstString(in: payload, keys: ["tool", "name", "function_name", "function"]),
        ].compactMap { $0 }

        for candidate in explicitCandidates {
            if let canonicalMCP = canonicalMCPToolName(from: candidate) {
                return canonicalMCP
            }
        }
        return nil
    }

    private static func canonicalMCPToolName(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fragments = trimmed
            .split(whereSeparator: { ch in
                ch == "." || ch == ":" || ch == "/" || ch == "\\" || ch == "_"
            })
            .map(String.init)

        var candidates: [String] = [trimmed.lowercased()]
        for index in fragments.indices {
            let tail = fragments[index...].joined(separator: "_").lowercased()
            guard !tail.isEmpty else { continue }
            candidates.append(tail)
            if tail.hasPrefix("coderide_") {
                candidates.append(tail)
            } else {
                candidates.append("coderide_" + tail)
            }
        }

        let registry = CoderIDECanonicalToolRegistry.shared
        for candidate in candidates {
            if registry.runtimeName(forMCPName: candidate) != nil {
                return candidate
            }
        }
        return nil
    }
}
