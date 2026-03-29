import Foundation
import SwiftUI

struct TerminalActivitySession: Identifiable {
    let id: String
    let title: String
    let command: String
    let cwd: String?
    let output: String?
    let stderr: String?
    let timestamp: Date
    let isRunning: Bool
    let sourceActivityId: UUID
    let groupId: String?
    let toolCallId: String?
    let status: String?

    init(
        id: String,
        title: String,
        command: String,
        cwd: String?,
        output: String?,
        stderr: String?,
        timestamp: Date,
        isRunning: Bool,
        sourceActivityId: UUID,
        groupId: String?,
        toolCallId: String?,
        status: String?
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.cwd = cwd
        self.output = output
        self.stderr = stderr
        self.timestamp = timestamp
        self.isRunning = isRunning
        self.sourceActivityId = sourceActivityId
        self.groupId = groupId
        self.toolCallId = toolCallId
        self.status = status
    }

    init(from activity: TaskActivity) {
        let normalizedStatus = activity.payload["status"]?.lowercased()
        sourceActivityId = activity.id
        toolCallId = activity.payload["tool_call_id"]
            ?? activity.payload["toolCallId"]
            ?? activity.payload["call_id"]
            ?? activity.payload["callId"]
        groupId = activity.groupId ?? activity.payload["group_id"] ?? activity.payload["groupId"]
        id = toolCallId ?? groupId ?? activity.id.uuidString
        title = activity.title
        command = activity.payload["command"] ?? activity.detail ?? activity.title
        cwd = activity.payload["cwd"]
        output = activity.payload["output"]
        stderr = activity.payload["stderr"]
        timestamp = activity.timestamp
        status = normalizedStatus
        isRunning = Self.normalizedRunningState(
            status: normalizedStatus,
            fallbackIsRunning: activity.isRunning
        )
    }
}
