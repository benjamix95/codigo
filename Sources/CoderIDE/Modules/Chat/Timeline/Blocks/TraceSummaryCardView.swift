import SwiftUI

struct TraceSummaryCardView: View {
    let traceEvents: [ToolTraceEvent]
    let context: ProjectContext?
    let onOpenFile: (String) -> Void

    var body: some View {
        if !traceEvents.isEmpty {
            MessageToolTraceView(
                events: traceEvents,
                workspaceHints: context?.folderPaths ?? [],
                onOpenFile: onOpenFile
            )
            .frame(maxWidth: 800, alignment: .leading)
        }
    }
}
