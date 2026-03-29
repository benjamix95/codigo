import Foundation

struct ChatTurnInlineTerminalDetail: Equatable {
    let command: String
    let output: String?
    let stderr: String?
    let exitCode: String?
    let cwd: String?
    let isRunning: Bool

    static func from(event: ToolTraceEvent, normalizedTool: String) -> ChatTurnInlineTerminalDetail? {
        let normalizedType = event.type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedType == "bash" || normalizedType == "command_execution" || normalizedTool == "bash" else {
            return nil
        }

        let command = firstNonEmpty([
            event.payload["command"],
            event.payload["cmd"],
            event.detail,
            event.title,
        ]) ?? event.title

        return ChatTurnInlineTerminalDetail(
            command: command,
            output: firstNonEmpty([event.payload["output"], event.payload["stdout"]]),
            stderr: firstNonEmpty([event.payload["stderr"]]),
            exitCode: firstNonEmpty([
                event.payload["exitCode"],
                event.payload["exit_code"],
                event.payload["code"],
            ]),
            cwd: firstNonEmpty([
                event.payload["cwd"],
                event.payload["workdir"],
                event.payload["working_directory"],
            ]),
            isRunning: event.isRunning
        )
    }

    var hasVisibleDetails: Bool {
        isRunning
            || !(output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(stderr?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(exitCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
