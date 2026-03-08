import SwiftUI

struct MessageToolTraceView: View {
    let events: [ToolTraceEvent]
    let workspaceHints: [String]
    let onOpenFile: (String) -> Void
    var onInteractionStart: (() -> Void)? = nil

    @State var expandedIds: Set<UUID> = []
    @State var derivedCache = DerivedCache()
    @State var isExpanded = false
    @State var didAutoCompactAfterCompletion = false
    @State var userDidManuallyExpand = false
    @State var expandedFileIds: Set<UUID> = []
    @State var filePreviewByEventId: [UUID: FileChangePreviewResult] = [:]
    @State var loadingPreviewIds: Set<UUID> = []
    @State var isCompactDiffExpanded = false
    @State var isCompactDiffLoading = false
    @State var isHoveringHeader = false

    let runningCompactLimit = 8

    var body: some View {
        let derived = currentDerived()
        VStack(alignment: .leading, spacing: 0) {
            headerView(derived: derived)

            if derived.shouldShowRows {
                VStack(alignment: .leading, spacing: 0) {
                    if derived.hiddenEventsCount > 0 && !isExpanded {
                        hiddenEventsButton(count: derived.hiddenEventsCount)
                    }

                    ForEach(Array(derived.genericDisplayEvents.enumerated()), id: \.element.id) { index, event in
                        traceRow(
                            event,
                            displayIndex: index + 1 + derived.hiddenEventsCount,
                            compactMode: !isExpanded,
                            derived: derived
                        )
                    }

                    if isExpanded, !derived.fileChanges.isEmpty {
                        fileChangesSectionView(derived: derived)
                            .padding(.top, 4)
                    }

                    if isExpanded, derived.hasRunningEvent {
                        collapseShortcutRow
                            .padding(.top, 6)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: 760, alignment: .leading)
        .onAppear {
            syncAutoPresentationState(derived: currentDerived())
        }
        .onChange(of: eventsChangeToken) { _ in
            syncAutoPresentationState(derived: currentDerived())
        }
        .onChange(of: isExpanded) { expanded in
            guard expanded else { return }
            let changes = currentDerived().fileChanges
            loadCompactDiffPreviewIfNeeded(changes: changes)
            for change in changes {
                loadPreviewIfNeeded(for: change)
            }
        }
    }
}
