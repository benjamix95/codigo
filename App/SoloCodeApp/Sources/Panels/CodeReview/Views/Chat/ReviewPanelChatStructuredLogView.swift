import SwiftUI

struct ReviewPanelChatStructuredLogView: View {
    let section: ReviewPanelChatStructuredSection

    private let bottomAnchorId = "review-panel-chat-structured-log-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(section.displayLines) { line in
                        Text(line.text)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.78))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorId)
                }
            }
            .frame(maxHeight: 180)
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: ReviewPanelChatAutoscroll.sectionLogFingerprint(section)) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        }
    }

}
