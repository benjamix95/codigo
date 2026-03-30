import Foundation

extension SwarmLiveReducer {
    enum NormalizedLifecycleStatus {
        case running
        case completed
        case failed
        case none
    }

    static func normalizedLifecycleStatus(_ activity: TaskActivity) -> NormalizedLifecycleStatus {
        if SubagentLaunchAcknowledgement.isLaunchAck(activity: activity) {
            return .running
        }
        let candidates = [
            activity.payload["status"],
            activity.detail,
            activity.payload["detail"],
            activity.title,
        ]
            .compactMap { $0 }
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .filter { !$0.isEmpty }

        if candidates.contains(where: isFailureLifecycleText(_:)) {
            return .failed
        }
        if candidates.contains(where: isCompletedLifecycleText(_:)) {
            return .completed
        }
        if candidates.contains(where: isRunningLifecycleText(_:)) || activity.isRunning {
            return .running
        }
        return .none
    }

    static func isFailureLifecycleText(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "-", with: "_")
        return normalized == "failed"
            || normalized == "error"
            || normalized == "fatal"
            || normalized == "blocked"
            || normalized == "cancelled"
            || normalized == "canceled"
            || normalized.contains(" failed")
            || normalized.contains(" error")
    }

    static func isCompletedLifecycleText(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "-", with: "_")
        return normalized == "completed"
            || normalized == "complete"
            || normalized == "done"
            || normalized == "success"
            || normalized == "successful"
            || normalized == "ok"
            || normalized == "finished"
            || normalized.contains(" completed")
            || normalized.contains(" done")
            || normalized.contains(" successful")
    }

    static func isRunningLifecycleText(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "-", with: "_")
        return normalized == "started"
            || normalized == "running"
            || normalized == "in_progress"
            || normalized.contains(" started")
            || normalized.contains(" running")
    }
}
