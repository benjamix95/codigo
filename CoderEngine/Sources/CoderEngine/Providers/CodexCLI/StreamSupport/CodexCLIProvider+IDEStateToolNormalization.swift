import Foundation

extension CodexCLIProvider {
    static func isFailureMCPToolStatus(_ normalizedStatus: String) -> Bool {
        IDEStateSyntheticEventFactory.isFailureStatus(normalizedStatus)
    }

    static func normalizeIDEStateMCPTool(_ rawTool: String) -> String {
        IDEStateSyntheticEventFactory.normalizeTool(rawTool)
    }

    static func isTerminalMCPToolStatus(_ normalizedStatus: String) -> Bool {
        let successfulTerminalStatuses: Set<String> = [
            "completed", "success", "done", "ok",
        ]
        return successfulTerminalStatuses.contains(normalizedStatus) || isFailureMCPToolStatus(normalizedStatus)
    }
}
