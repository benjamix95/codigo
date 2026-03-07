import SwiftUI
import CoderEngine

struct CodeReviewPanelView: View {
    @ObservedObject var taskActivityStore: TaskActivityStore

    let conversationId: UUID?
    let isTaskRunning: Bool
    let coderMode: CoderMode

    @Binding var codeReviewPartitions: Int
    @Binding var codeReviewAnalysisOnly: Bool
    @Binding var codeReviewMaxRounds: Int
    @Binding var codeReviewAnalysisBackend: String
    @Binding var codeReviewExecutionBackend: String

    let onClose: () -> Void
    let onOpenFile: (String) -> Void
    let onDispatchAction: (CodeReviewPanelAction) -> Void

    @State var againstCommitRef = ""
    @State var selectedTab: CodeReviewTab = .commands
    @State var selectedFindingId: String?
    @State var sessionBrowserExpanded = false

    var autofixEnabled: Bool { !codeReviewAnalysisOnly }
    func setAutofixEnabled(_ v: Bool) { codeReviewAnalysisOnly = !v }

    let topInteractiveInset: CGFloat = 22
    let accent = DesignSystem.Colors.reviewColor

    var body: some View {
        let m = metrics()
        let selectedSessionId = taskActivityStore.selectedCodeReviewSessionId(for: conversationId)
        VStack(spacing: 0) {
            Color.clear.frame(height: topInteractiveInset).allowsHitTesting(false)
            topBar(m)
            sessionBrowserCard
            Divider().opacity(0.3)
            tabSelector
            Divider().opacity(0.2)
            mainContent(m)
            Divider().opacity(0.2)
            bottomBar
        }
        .background(DesignSystem.Colors.chatPanelSolidBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .onChange(of: selectedSessionId) { _, _ in
            selectedFindingId = nil
        }
        .onChange(of: conversationId) { _, _ in
            selectedFindingId = nil
        }
    }
}
