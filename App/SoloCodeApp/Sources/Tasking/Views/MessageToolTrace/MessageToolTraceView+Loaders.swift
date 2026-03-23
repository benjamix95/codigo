import SwiftUI

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
                if isExpanded, compactDiffPreview(fileChanges: updatedChanges) != nil {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isCompactDiffExpanded = true
                    }
                }
            }
        }
    }

    func syncAutoPresentationState(derived: DerivedState) {
        let ordered = derived.orderedEvents
        let running = derived.hasRunningEvent
        if running {
            didAutoCompactAfterCompletion = false
            guard !isExpanded, !userDidManuallyCollapseWhileRunning else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded = true
            }
            return
        }
        guard !ordered.isEmpty else { return }
        guard !didAutoCompactAfterCompletion else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            isExpanded = false
            expandedIds.removeAll()
            expandedFileIds.removeAll()
            isCompactDiffExpanded = false
        }
        isCompactDiffLoading = false
        userDidManuallyExpand = false
        userDidManuallyCollapseWhileRunning = false
        didAutoCompactAfterCompletion = true
    }
}
