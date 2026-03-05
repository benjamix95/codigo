import SwiftUI

extension CodeReviewPanelView {
    // MARK: - Top Bar

    func topBar(_ m: CodeReviewMetrics) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
            Text("Code Review")
                .font(.system(size: 13, weight: .semibold))

            if let ri = m.roundInfo, isTaskRunning {
                Text("Round \(ri.round)/\(ri.maxRounds)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accent))
            }

            if m.activeCount > 0 {
                badge("\(m.activeCount) active", accent)
            }

            Spacer()

            if isTaskRunning && coderMode == .codeReviewMultiSwarm {
                ProgressView().controlSize(.mini)
            }

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Tab Selector

    var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(CodeReviewTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.15)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tabIcon(tab))
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selectedTab == tab ? accent : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedTab == tab ? accent.opacity(0.14) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    func mainContent(_ m: CodeReviewMetrics) -> some View {
        switch selectedTab {
        case .commands:
            commandsTab(m)
        case .findings:
            findingsTab
        case .timeline:
            timelineTab
        case .config:
            configTab
        }
    }

    // MARK: - Tab Icon

    private func tabIcon(_ tab: CodeReviewTab) -> String {
        switch tab {
        case .commands: return "terminal"
        case .findings: return "exclamationmark.triangle"
        case .timeline: return "clock"
        case .config: return "gearshape"
        }
    }
}
