import CoderEngine
import SwiftUI

/// Workspace a pannello pieno per un finding verificato (bug/security): dettaglio, delta, azioni, attività.
struct ReviewPanelFindingImmersiveShell: View {
    @ObservedObject var store: CodeReviewPanelStore
    let finding: CodeReviewFinding
    let onOpenFileAtLocation: (String, Int?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ReviewPanelFindingImmersiveHeader(store: store, finding: finding)
            ReviewPanelFindingDetail(
                store: store,
                finding: finding,
                onOpenFileAtLocation: onOpenFileAtLocation,
                onBack: { store.leaveImmersiveFindingWorkspace() },
                chrome: .immersive
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ReviewPanelFindingApplyActivityFooter(store: store, findingId: finding.id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
