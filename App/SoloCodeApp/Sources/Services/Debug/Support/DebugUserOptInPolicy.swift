import Foundation

func shouldHonorDebugUserOptIn(debugToggleEnabled: Bool) -> Bool {
    debugToggleEnabled
}

func shouldUseDebugUXContext(
    coderMode: CoderMode,
    showDebugPanel: Bool,
    debugToggleEnabled: Bool
) -> Bool {
    debugToggleEnabled && (coderMode == .debug || showDebugPanel)
}

func resolvedModeForConversation(
    requestedMode: CoderMode,
    debugToggleEnabled: Bool
) -> CoderMode {
    if requestedMode == .debug && !debugToggleEnabled {
        return .agent
    }
    return requestedMode
}

func shouldRouteDebugProjectionEvent(
    _ event: NormalizedEvent,
    debugToggleEnabled: Bool
) -> Bool {
    debugToggleEnabled && DebugProjectionEventConsumer.handles(event)
}

func shouldApplyDebugProjectionEffects(
    _ effects: DebugProjectionUIEffects,
    debugToggleEnabled: Bool
) -> Bool {
    debugToggleEnabled && (effects.shouldEnableDebugMode || effects.shouldRevealDebugPanel)
}

func shouldDisplayTaskActivity(
    type: String,
    debugToggleEnabled: Bool
) -> Bool {
    debugToggleEnabled || !isDebugControlTaskActivity(type: type)
}

private func isDebugControlTaskActivity(type: String) -> Bool {
    let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized == "activate_debug_mode" || normalized.hasPrefix("debug_")
}
