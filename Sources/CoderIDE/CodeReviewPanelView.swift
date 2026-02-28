import SwiftUI
import CoderEngine

/// Cursor-style sidebar panel for Code Review operations.
/// Provides quick-access slash commands, against-commit review,
/// and an autofix loop with live status.
struct CodeReviewPanelView: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var swarmProgressStore: SwarmProgressStore
    @ObservedObject var todoStore: TodoStore

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
    let onRunSlashCommand: (String) -> Void
    let onSelectMode: (CoderMode) -> Void

    // MARK: - Local State

    @State private var againstCommitRef = ""
    @State private var selectedTab: ReviewTab = .commands

    /// Derived from codeReviewAnalysisOnly binding (inverted)
    private var autofixEnabled: Bool { !codeReviewAnalysisOnly }
    private func setAutofixEnabled(_ enabled: Bool) { codeReviewAnalysisOnly = !enabled }

    private let topInteractiveInset: CGFloat = 22
    private let reviewColor = DesignSystem.Colors.reviewColor

    enum ReviewTab: String, CaseIterable {
        case commands = "Commands"
        case config = "Config"
    }

    // MARK: - Derived Data

    private typealias WorkerInfoRow = (
        id: String, description: String, severity: String, fileCount: String, files: String
    )

    private struct PanelMetrics {
        let reviewCards: [SwarmLiveCardState]
        let activeReviewCount: Int
        let workerInfo: [WorkerInfoRow]
        let currentRoundInfo: (round: String, maxRounds: String)?
    }

    private func panelMetrics() -> PanelMetrics {
        // Filter out orchestrator — only show real review workers
        let cards = SwarmLiveReducer.sorted(states: taskActivityStore.swarmCardStates())
            .filter { $0.swarmId != "orchestrator" }
        let activeCount = cards.filter { $0.status == .running }.count

        let activities = taskActivityStore.activities
        let workers: [WorkerInfoRow] = activities.compactMap { activity in
            guard activity.type == "review-worker-plan",
                  let wid = activity.payload["worker_id"],
                  let desc = activity.payload["description"],
                  let severity = activity.payload["severity"],
                  let fileCount = activity.payload["fileCount"],
                  let files = activity.payload["files"] else {
                return nil
            }
            return (wid, desc, severity, fileCount, files)
        }

        let roundInfo = activities.reversed().compactMap { activity -> (String, String)? in
            guard activity.type == "review-fix-round",
                  let round = activity.payload["round"],
                  let maxRounds = activity.payload["maxRounds"] else {
                return nil
            }
            return (round, maxRounds)
        }.first

        return PanelMetrics(
            reviewCards: cards,
            activeReviewCount: activeCount,
            workerInfo: workers,
            currentRoundInfo: roundInfo
        )
    }

    // MARK: - Body

    var body: some View {
        let metrics = panelMetrics()
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)
            topBar(metrics: metrics)
            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
            tabSelector
            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
            mainContent(metrics: metrics)
            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
            bottomBar
        }
        .background(DesignSystem.Colors.chatPanelSolidBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }

    // MARK: - Top Bar

    private func topBar(metrics: PanelMetrics) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(reviewColor)
            Text("Code Review")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            if isTaskRunning && coderMode == .codeReviewMultiSwarm {
                Circle()
                    .fill(reviewColor)
                    .frame(width: 6, height: 6)
                    .modifier(PulseModifier())
            }
            Spacer()

            // Round counter badge
            if let roundInfo = metrics.currentRoundInfo, isTaskRunning {
                Text("Round \(roundInfo.round)/\(roundInfo.maxRounds)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(reviewColor))
            }

            if metrics.activeReviewCount > 0 {
                Text("\(metrics.activeReviewCount) active")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(reviewColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(reviewColor.opacity(0.12))
                    )
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(Color(nsColor: .separatorColor).opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 2) {
            ForEach(ReviewTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selectedTab == tab ? reviewColor : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selectedTab == tab ? reviewColor.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(metrics: PanelMetrics) -> some View {
        switch selectedTab {
        case .commands:
            commandsTab(metrics: metrics)
        case .config:
            configTab
        }
    }

    // MARK: - Commands Tab

    private func commandsTab(metrics: PanelMetrics) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Against-commit section
                againstCommitSection

                Divider().opacity(0.3)

                // Quick slash commands
                slashCommandsSection

                Divider().opacity(0.3)

                // Dynamic worker info during live review
                if coderMode == .codeReviewMultiSwarm && !metrics.workerInfo.isEmpty {
                    workerInfoSection(workerInfo: metrics.workerInfo)
                    Divider().opacity(0.3)
                }

                // Live review status
                if coderMode == .codeReviewMultiSwarm && !metrics.reviewCards.isEmpty {
                    liveStatusSection(reviewCards: metrics.reviewCards)
                }
            }
            .padding(14)
        }
    }

    // MARK: - Against Commit Section

    private var againstCommitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Against Commit", systemImage: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Review changes against a specific commit reference.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("HEAD~1, abc123, main..feature", text: $againstCommitRef)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity)

                Button {
                    runAgainstCommitReview()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(reviewColor)
                        )
                }
                .buttonStyle(.plain)
                .disabled(againstCommitRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTaskRunning)
                .help("Run review against commit")
            }

            // Autofix toggle
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { autofixEnabled },
                    set: { setAutofixEnabled($0) }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                        Text("Autofix Loop")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()

                if autofixEnabled {
                    Text("max \(codeReviewMaxRounds) rounds")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Slash Commands Section

    private var slashCommandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quick Commands", systemImage: "terminal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            ForEach(slashCommands, id: \.id) { cmd in
                Button {
                    // Switch to review mode first if needed
                    if coderMode != .codeReviewMultiSwarm {
                        onSelectMode(.codeReviewMultiSwarm)
                    }
                    onRunSlashCommand(cmd.prompt)
                } label: {
                    HStack(spacing: 8) {
                        Text(cmd.slash)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(reviewColor)
                        Spacer()
                        Text(cmd.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTaskRunning)
            }
        }
    }

    // MARK: - Worker Info Section

    private func workerInfoSection(workerInfo: [WorkerInfoRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Dynamic Workers", systemImage: "person.3.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            ForEach(workerInfo, id: \.id) { info in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(info.id.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(reviewColor)
                        Spacer()
                        severityBadge(info.severity)
                        Text("\(info.fileCount) files")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(info.description)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(info.files)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                )
            }
        }
    }

    private func severityBadge(_ severity: String) -> some View {
        let color: Color = switch severity.lowercased() {
        case "critical": .red
        case "warning": .orange
        default: .blue
        }
        return Text(severity.capitalized)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
    }

    // MARK: - Live Status Section

    private func liveStatusSection(reviewCards: [SwarmLiveCardState]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Live Status", systemImage: "waveform.path.ecg")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            ForEach(Array(reviewCards.prefix(10)), id: \.swarmId) { card in
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(for: card.status))
                        .frame(width: 6, height: 6)
                    Text(card.swarmId)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(card.status.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                )
            }
        }
    }

    // MARK: - Config Tab

    private var configTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Max Workers
                configSection(title: "Max Workers", icon: "person.3.fill") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max concurrent workers")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Stepper(value: $codeReviewPartitions, in: 1...12) {
                                Text("\(codeReviewPartitions)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(reviewColor)
                            }
                            .fixedSize()
                        }
                        Text("The analysis LLM decides how many workers to spawn (up to this limit)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Max rounds
                configSection(title: "Max Review Rounds", icon: "arrow.triangle.2.circlepath") {
                    HStack {
                        Stepper(value: $codeReviewMaxRounds, in: 1...10) {
                            Text("\(codeReviewMaxRounds)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(reviewColor)
                        }
                        .fixedSize()
                        Text("rounds per autofix loop")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                // Analysis only toggle
                configSection(title: "Mode", icon: "eye") {
                    Toggle(isOn: $codeReviewAnalysisOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Analysis Only")
                                .font(.system(size: 11, weight: .medium))
                            Text("Skip autofix, report findings only")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                // Analysis backend
                configSection(title: "Analysis Backend", icon: "cpu") {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $codeReviewAnalysisBackend) {
                            Text("Auto (same as Agent)").tag("auto")
                            Text("Codex CLI").tag("codex-cli")
                            Text("Claude Code").tag("claude-cli")
                            Text("Anthropic API").tag("anthropic-api")
                            Text("OpenAI API").tag("openai-api")
                            Text("Google API").tag("google-api")
                            Text("OpenRouter API").tag("openrouter-api")
                        }
                        .pickerStyle(.menu)
                        .fixedSize()

                        if codeReviewAnalysisBackend == "auto" {
                            Text("Uses the same provider selected in Agent tab")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Execution backend
                if !codeReviewAnalysisOnly {
                    configSection(title: "Execution Backend", icon: "hammer") {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("", selection: $codeReviewExecutionBackend) {
                                Text("Auto (same as Agent)").tag("auto")
                                Text("Codex CLI").tag("codex-cli")
                                Text("Claude Code").tag("claude-cli")
                                Text("Anthropic API").tag("anthropic-api")
                                Text("OpenAI API").tag("openai-api")
                                Text("Google API").tag("google-api")
                                Text("OpenRouter API").tag("openrouter-api")
                            }
                            .pickerStyle(.menu)
                            .fixedSize()

                            if codeReviewExecutionBackend == "auto" {
                                Text("Uses the same provider selected in Agent tab")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func configSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            if coderMode != .codeReviewMultiSwarm {
                Button {
                    onSelectMode(.codeReviewMultiSwarm)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 10))
                        Text("Activate Review Mode")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(reviewColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(reviewColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(reviewColor)
                Text("Review mode active")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(reviewColor)
            }
            Spacer()

            // Commit & Push action button (shown when review is not running)
            if coderMode == .codeReviewMultiSwarm && !isTaskRunning {
                Button {
                    onRunSlashCommand("""
                        Stage all changes and create a clean atomic commit with a descriptive commit message.
                        Then push to the remote. Requirements: green build/tests before committing.
                        """)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10))
                        Text("Commit & Push")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(reviewColor)
                    )
                }
                .buttonStyle(.plain)
                .help("Commit fixes and push to remote")
            }

            if isTaskRunning && coderMode == .codeReviewMultiSwarm {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func runAgainstCommitReview() {
        let ref = againstCommitRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { return }

        // Switch to review mode if needed
        if coderMode != .codeReviewMultiSwarm {
            onSelectMode(.codeReviewMultiSwarm)
        }

        let autofixSuffix = autofixEnabled
            ? "\nAfter analysis, apply all confirmed fixes. Run build/tests and iterate up to \(codeReviewMaxRounds) rounds until clean."
            : "\nAnalysis only — report findings with priority/confidence, do NOT apply fixes."

        // Prefix prompt with [AGAINST:ref] so the provider knows the commit scope
        let prompt = """
            [AGAINST:\(ref)] Run deep code review on changes from \(ref) to HEAD.
            Scope: all modified, added, and renamed files in that range.
            Required output:
            1) prioritized findings (P0-P3) with file:line references,
            2) regression risks,
            3) final verdict on patch correctness.\(autofixSuffix)
            """

        onRunSlashCommand(prompt)
    }

    // MARK: - Slash Command Presets

    private struct SlashCommand: Identifiable {
        let id: String
        let slash: String
        let label: String
        let prompt: String
    }

    private var slashCommands: [SlashCommand] {
        [
            SlashCommand(
                id: "review-uncommitted",
                slash: "/review-uncommitted",
                label: "Full uncommitted audit",
                prompt: """
                    Run ultra-deep code review on all uncommitted changes (staged, unstaged, untracked).
                    Required output:
                    1) prioritized findings (P0-P3),
                    2) impacted areas file-by-file,
                    3) regression risks,
                    4) final verdict on patch correctness.
                    """
            ),
            SlashCommand(
                id: "review-staged",
                slash: "/review-staged",
                label: "Staged diff only",
                prompt: """
                    Review ONLY staged changes.
                    Ignore unstaged and untracked.
                    Return severe and actionable findings with priority/confidence.
                    """
            ),
            SlashCommand(
                id: "review-autofix",
                slash: "/review-autofix",
                label: "Review + auto fix",
                prompt: """
                    Deep review uncommitted changes and directly fix all confirmed bugs.
                    After fixes, run relevant build/tests and report the technical changelog.
                    """
            ),
            SlashCommand(
                id: "review-autofix-commit",
                slash: "/review-autofix-commit",
                label: "Review + fix + commit",
                prompt: """
                    Run full review on staged/unstaged/untracked, apply necessary fixes and create final atomic commit.
                    Requirements: no superfluous changes, green build/tests, specific commit message.
                    """
            ),
            SlashCommand(
                id: "review-focus-ui",
                slash: "/review-focus-ui",
                label: "Focus UI flows",
                prompt: """
                    Focus on review realtime flows:
                    - visible step-by-step stream,
                    - live updated read/tool/terminal cards,
                    - consistent todos without layout glitches.
                    Fix any issues found and validate with tests/build.
                    """
            ),
        ]
    }

    // MARK: - Helpers

    private func statusColor(for status: SwarmCardStatus) -> Color {
        switch status {
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .idle: return .orange
        }
    }
}
