import Foundation

struct InlineToolTraceGroupAutoPresentationState: Equatable {
    var isExpanded: Bool
    var didAutoCollapseAfterCompletion: Bool
}

enum InlineToolTraceGroupAutoPresentation {
    static func initialState(
        hasRunningEvent: Bool,
        hasEvents: Bool
    ) -> InlineToolTraceGroupAutoPresentationState {
        InlineToolTraceGroupAutoPresentationState(
            isExpanded: hasRunningEvent,
            didAutoCollapseAfterCompletion: hasEvents && !hasRunningEvent
        )
    }

    static func reconcile(
        current: InlineToolTraceGroupAutoPresentationState,
        hasRunningEvent: Bool,
        hasEvents: Bool
    ) -> InlineToolTraceGroupAutoPresentationState {
        if hasRunningEvent {
            var updated = current
            updated.didAutoCollapseAfterCompletion = false
            return updated
        }

        guard hasEvents, !current.didAutoCollapseAfterCompletion else {
            return current
        }

        return InlineToolTraceGroupAutoPresentationState(
            isExpanded: false,
            didAutoCollapseAfterCompletion: true
        )
    }
}
