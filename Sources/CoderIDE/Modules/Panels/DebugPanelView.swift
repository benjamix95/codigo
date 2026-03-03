import SwiftUI
import CoderEngine

struct DebugPanelView: View {
    @ObservedObject var debugStore: DebugStore
    let taskActivities: [TaskActivity]
    @ObservedObject var todoStore: TodoStore
    let onClose: () -> Void
    let onSubmitQuestion: (String) -> Void
    let onStop: () -> Void
    let onProceed: () -> Void
    let onFixed: () -> Void

    @State var userInput = ""
    @State var expandedLogId: UUID?
    @State var selectedTab: DebugTab = .logs
    @State var expandedRuntimeLogId: String?
    @State var isFilterExpanded = false
    @State var hoveredPhase: DebugFlowPhase?
    @FocusState var isChatInputFocused: Bool
    @State var showPhaseDetail = false

    let topInteractiveInset: CGFloat = 22
    let accent = DesignSystem.Colors.debugColor

    enum DebugTab: String, CaseIterable {
        case logs = "Logs"
        case runtime = "Runtime"
        case hypotheses = "Hypotheses"
        case markers = "Markers"

        var icon: String {
            switch self {
            case .logs:       return "doc.text"
            case .runtime:    return "waveform.path.ecg"
            case .hypotheses: return "lightbulb"
            case .markers:    return "mappin"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)

            header
            divider

            if debugStore.phase != .idle {
                phaseTimeline
                    .transition(.move(edge: .top).combined(with: .opacity))
                divider
            }

            tabStrip
            divider

            scrollContent

            if debugStore.phase != .idle && debugStore.phase != .resolved {
                if !debugStore.streamingContent.isEmpty {
                    divider
                    streamingBanner
                }
                if !debugStore.clarificationQuestions.isEmpty {
                    divider
                    questionCards
                }
            }

            phaseActionArea

            divider
            chatInput
        }
        .background(DesignSystem.Colors.chatPanelSolidBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        )
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)
        .animation(.smooth, value: debugStore.phase)
        .animation(.smooth, value: selectedTab)
    }
}
