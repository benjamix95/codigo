import SwiftUI

struct ReviewPanelChatStructuredLogView: View {
    let section: ReviewPanelChatStructuredSection

    private let bottomAnchorId = "review-panel-chat-structured-log-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.78))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(logLineId(for: index))
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
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
    }

    private func logLineId(for index: Int) -> String {
        "\(section.id)-line-\(index)"
    }
}
