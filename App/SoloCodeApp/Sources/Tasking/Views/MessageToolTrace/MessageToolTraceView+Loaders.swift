import SwiftUI

struct MessageToolTraceAutoPresentationState: Equatable {
    var isExpanded: Bool
    var didAutoCompactAfterCompletion: Bool
    var userDidManuallyExpand: Bool
    var userDidManuallyCollapseWhileRunning: Bool
    var isCompactDiffExpanded: Bool
    var isCompactDiffLoading: Bool
}

enum MessageToolTraceAutoPresentation {
    static func reconcile(
        current: MessageToolTraceAutoPresentationState,
        hasRunningEvent: Bool,
        hasOrderedEvents: Bool
    ) -> MessageToolTraceAutoPresentationState {
        if hasRunningEvent {
            var updated = current
            updated.didAutoCompactAfterCompletion = false
            // Never auto-expand while running. Expansion is manual only.
            return updated
        }

        guard hasOrderedEvents, !current.didAutoCompactAfterCompletion else {
            return current
        }

        return MessageToolTraceAutoPresentationState(
            isExpanded: false,
            didAutoCompactAfterCompletion: true,
            userDidManuallyExpand: false,
            userDidManuallyCollapseWhileRunning: false,
            isCompactDiffExpanded: false,
            isCompactDiffLoading: false
        )
    }

    static func shouldAutoExpandCompactDiff(
        isTraceExpanded: Bool,
        hasPreview: Bool
    ) -> Bool {
        // Keep file-change previews closed until the user explicitly expands them.
        let _ = isTraceExpanded
        let _ = hasPreview
        return false
    }
}

extension MessageToolTraceView {
    func collapseSupersededToolStates(_ input: [ToolTraceEvent]) -> [ToolTraceEvent] {
        ToolTraceEventCollapser.collapseSupersededToolStates(input)
    }

    func toggleExpandedFile(_ change: ToolTraceFileChange) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if expandedFileIds.contains(change.id) {
                expandedFileIds.remove(change.id)
                return
            }
            expandedFileIds.insert(change.id)
        }
        loadPreviewIfNeeded(for: change)
    }

    func openFileForChange(_ change: ToolTraceFileChange) {
        guard let path = FileChangePreviewResolver.resolveOpenPath(
            for: change,
            workspaceHints: workspaceHints
        ) else {
            return
        }
        onOpenFile(path)
    }

    func loadPreviewIfNeeded(for change: ToolTraceFileChange) {
        if filePreviewByEventId[change.id] != nil || loadingPreviewIds.contains(change.id) {
            return
        }
        loadingPreviewIds.insert(change.id)
        Task {
            let result = await FileChangePreviewResolver.shared.resolvePreview(
                for: change,
                workspaceHints: workspaceHints
            )
            await MainActor.run {
                filePreviewByEventId[change.id] = result
                loadingPreviewIds.remove(change.id)
            }
        }
    }

    func loadCompactDiffPreviewIfNeeded(changes initialChanges: [ToolTraceFileChange]? = nil) {
        guard !isCompactDiffLoading else { return }
        let changes = initialChanges ?? currentDerived().fileChanges
        guard !changes.isEmpty else { return }
        isCompactDiffLoading = true

        Task {
            for change in changes {
                if compactDiffChunk(for: change) != nil {
                    continue
                }
                let result = await FileChangePreviewResolver.shared.resolvePreview(
                    for: change,
                    workspaceHints: workspaceHints
                )
                await MainActor.run {
                    filePreviewByEventId[change.id] = result
                }
            }

            await MainActor.run {
                isCompactDiffLoading = false
                let updatedChanges = currentDerived().fileChanges
                if MessageToolTraceAutoPresentation.shouldAutoExpandCompactDiff(
                    isTraceExpanded: isExpanded,
                    hasPreview: compactDiffPreview(fileChanges: updatedChanges) != nil
                ) {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isCompactDiffExpanded = true
                    }
                }
            }
        }
    }

    func syncAutoPresentationState(derived: DerivedState) {
        let current = MessageToolTraceAutoPresentationState(
            isExpanded: isExpanded,
            didAutoCompactAfterCompletion: didAutoCompactAfterCompletion,
            userDidManuallyExpand: userDidManuallyExpand,
            userDidManuallyCollapseWhileRunning: userDidManuallyCollapseWhileRunning,
            isCompactDiffExpanded: isCompactDiffExpanded,
            isCompactDiffLoading: isCompactDiffLoading
        )
        let next = MessageToolTraceAutoPresentation.reconcile(
            current: current,
            hasRunningEvent: derived.hasRunningEvent,
            hasOrderedEvents: !derived.orderedEvents.isEmpty
        )

        didAutoCompactAfterCompletion = next.didAutoCompactAfterCompletion

        guard next != current else { return }

        withAnimation(.easeOut(duration: 0.15)) {
            isExpanded = next.isExpanded
            isCompactDiffExpanded = next.isCompactDiffExpanded
            if !next.isExpanded {
                expandedIds.removeAll()
                expandedFileIds.removeAll()
            }
        }
        isCompactDiffLoading = next.isCompactDiffLoading
        userDidManuallyExpand = next.userDidManuallyExpand
        userDidManuallyCollapseWhileRunning = next.userDidManuallyCollapseWhileRunning
    }
}
