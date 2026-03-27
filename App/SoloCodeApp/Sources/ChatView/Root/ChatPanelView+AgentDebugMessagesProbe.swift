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
            }
    }

    private func logLayout(_ h: CGFloat, phase: String) {
    }
}
