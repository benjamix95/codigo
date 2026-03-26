import SwiftUI

// MARK: - Agent debug (session fba6fd): layout + stato messaggi — rimuovere dopo verifica.

struct ChatPanelMessagesDebugModifier: ViewModifier {
    let storeMessageCount: Int
    let snapshotCount: Int
    let snapshotIsNil: Bool
    let showEmptyOverlay: Bool
    let isLoading: Bool

    @State private var lastAreaHeight: CGFloat = -1
    @State private var sawLowHeight = false

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            logLayout(geo.size.height, phase: "appear")
                        }
                        .onChange(of: geo.size.height) { newH in
                            logLayout(newH, phase: "change")
                        }
                }
            }
            .onChange(of: showEmptyOverlay) { new in
                // #region agent log
                // Rileva solo incoerenze: il Bool passato qui può disallinearsi dai `let` del modifier
                // tra un frame e l’onChange (falso H2). La policy reale e i log atomici sono in
                // `shouldShowMessagesAreaEmptyState`.
                if new, storeMessageCount > 0 || snapshotCount > 0 {
                    AgentDebugSessionNDJSONLog.append(
                        hypothesisId: "H2-modifier-inconsistent",
                        location: "ChatPanelMessagesDebugModifier",
                        message: "overlay_true_but_counts_nonzero_modifier_snapshot",
                        data: [
                            "storeMessageCount": "\(storeMessageCount)",
                            "snapshotCount": "\(snapshotCount)",
                            "snapshotIsNil": "\(snapshotIsNil)",
                            "isLoading": "\(isLoading)",
                        ]
                    )
                }
                // #endregion
            }
    }

    private func logLayout(_ h: CGFloat, phase: String) {
        // #region agent log
        if h >= 0, h < 16 {
            AgentDebugSessionNDJSONLog.append(
                hypothesisId: "H5",
                location: "ChatPanelMessagesDebugModifier",
                message: "messages_area_very_small_height",
                data: ["height": "\(h)", "phase": phase]
            )
            sawLowHeight = true
        } else if sawLowHeight, h > 80 {
            AgentDebugSessionNDJSONLog.append(
                hypothesisId: "H5",
                location: "ChatPanelMessagesDebugModifier",
                message: "messages_area_height_recovered_after_low",
                data: ["height": "\(h)", "phase": phase]
            )
            sawLowHeight = false
        }
        let prev = lastAreaHeight
        if prev > 40, h < prev * 0.25, h < 40 {
            AgentDebugSessionNDJSONLog.append(
                hypothesisId: "H5",
                location: "ChatPanelMessagesDebugModifier",
                message: "messages_area_height_collapsed",
                data: [
                    "height": "\(h)",
                    "prev": "\(prev)",
                    "phase": phase,
                ]
            )
        }
        lastAreaHeight = h
        // #endregion
    }
}
