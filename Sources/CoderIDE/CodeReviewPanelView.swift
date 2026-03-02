import SwiftUI
import CoderEngine

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

    @State private var againstCommitRef = ""
    @State private var selectedTab: ReviewTab = .commands

    private var autofixEnabled: Bool { !codeReviewAnalysisOnly }
    private func setAutofixEnabled(_ v: Bool) { codeReviewAnalysisOnly = !v }

    private let topInteractiveInset: CGFloat = 22
    private let accent = DesignSystem.Colors.reviewColor

    enum ReviewTab: String, CaseIterable {
        case commands = "Commands"
        case config = "Config"
    }

    // MARK: - Metrics

    private struct WorkerRow: Identifiable {
        let id: String
        let description: String
        let severity: String
        let fileCount: Int
        let files: [String]
        let filesSummary: String
    }

    private struct Metrics {
        let cards: [SwarmLiveCardState]
        let activeCount: Int
        let workers: [WorkerRow]
        let roundInfo: (round: String, maxRounds: String)?
    }

    private func metrics() -> Metrics {
        guard coderMode == .codeReviewMultiSwarm else {
            return Metrics(cards: [], activeCount: 0, workers: [], roundInfo: nil)
        }
        let activities = scopedTaskActivitiesForConversation(
            taskActivityStore.activities,
            conversationId: conversationId
        )
        let cards = taskActivityStore
            .swarmCardStates()
            .filter {
                $0.swarmId.hasPrefix("review-")
                    && reviewCardBelongsToConversation($0, conversationId: conversationId)
            }
        let active = cards.filter { $0.status == .running }.count

        let workerActivities = sortedReviewWorkerPlanActivitiesForDisplay(
            selectReviewWorkerActivities(from: activities)
        )

        let workers: [WorkerRow] = workerActivities.compactMap { a in
            guard let wid = a.payload["worker_id"],
                  let desc = a.payload["description"],
                  let sev = a.payload["severity"],
                  let fcRaw = a.payload["fileCount"] else { return nil }
            let fileCount = Int(fcRaw) ?? 0
            let summary = a.payload["files"] ?? ""
            let rawFiles = (a.payload["files_raw"] ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return WorkerRow(
                id: wid,
                description: desc,
                severity: sev,
                fileCount: fileCount,
                files: rawFiles,
                filesSummary: summary
            )
        }

        let round: (String, String)? = if coderMode == .codeReviewMultiSwarm {
            activities.reversed().compactMap { a -> (String, String)? in
                guard a.type == "review-fix-round",
                      let r = a.payload["round"],
                      let m = a.payload["maxRounds"] else { return nil }
                return (r, m)
            }.first
        } else { nil }

        return Metrics(cards: cards, activeCount: active, workers: workers, roundInfo: round)
    }

    // MARK: - Body

    var body: some View {
        let m = metrics()
        VStack(spacing: 0) {
            Color.clear.frame(height: topInteractiveInset).allowsHitTesting(false)
            topBar(m)
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
    }

    // MARK: - Top Bar

    private func topBar(_ m: Metrics) -> some View {
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

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(ReviewTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.15)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab == .commands ? "terminal" : "gearshape")
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

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(_ m: Metrics) -> some View {
        switch selectedTab {
        case .commands: commandsTab(m)
        case .config: configTab
        }
    }

    // MARK: - Commands Tab

    private func commandsTab(_ m: Metrics) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                againstCommitCard
                slashCommandsCard

                if !m.workers.isEmpty {
                    workersCard(m.workers)
                }

                if !m.cards.isEmpty {
                    liveStatusCard(m.cards)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Against Commit Card

    private var againstCommitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text("AGAINST COMMIT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }

            Text("Review changes against a specific commit reference")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("HEAD~1, abc123, main..feature", text: $againstCommitRef)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity)

                Button { runAgainstCommitReview() } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent))
                }
                .buttonStyle(.plain)
                .disabled(!isValidGitRef(againstCommitRef) || isTaskRunning)
            }

            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { autofixEnabled }, set: { setAutofixEnabled($0) })) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                        Text("Autofix")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(isTaskRunning)
                Spacer()
                if autofixEnabled {
                    Text("max \(codeReviewMaxRounds) rounds")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Slash Commands Card

    private var slashCommandsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text("QUICK COMMANDS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }

            ForEach(slashCommands, id: \.id) { cmd in
                Button {
                    if coderMode != .codeReviewMultiSwarm {
                        onSelectMode(.codeReviewMultiSwarm)
                        // Yield to the next main-actor turn so SwiftUI processes
                        // the mode change before the command runs (deterministic
                        // vs. the previous hardcoded 150ms asyncAfter race).
                        Task { @MainActor in
                            onRunSlashCommand(cmd.prompt)
                        }
                    } else {
                        onRunSlashCommand(cmd.prompt)
                    }
                } label: {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(accent.opacity(0.6))
                            .frame(width: 2.5)
                            .padding(.vertical, 3)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(cmd.slash)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(accent)
                            Text(cmd.label)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.leading, 8)
                        .padding(.vertical, 5)

                        Spacer(minLength: 4)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.quaternary)
                            .padding(.trailing, 8)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTaskRunning)
            }
        }
    }

    // MARK: - Workers Card

    private func workersCard(_ workers: [WorkerRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text("WORKERS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Spacer()
                Text("\(workers.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            ForEach(workers, id: \.id) { w in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(severityColor(w.severity))
                        .frame(width: 2.5)
                        .padding(.vertical, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(w.id.uppercased())
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)
                            Spacer(minLength: 4)
                            severityBadge(w.severity)
                        Text("\(w.fileCount) files")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                        Text(w.description)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(2)
                        if !w.files.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(Array(w.files.enumerated()), id: \.offset) { _, path in
                                        Button {
                                            onOpenFile(path)
                                        } label: {
                                            Text((path as NSString).lastPathComponent)
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundStyle(accent)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(accent.opacity(0.12), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .help(path)
                                    }
                                }
                            }
                        } else if !w.filesSummary.isEmpty {
                            Text(w.filesSummary)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 5)
                    .padding(.trailing, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                )
            }
        }
    }

    private func severityColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "critical": return DesignSystem.Colors.error
        case "warning": return DesignSystem.Colors.warning
        default: return DesignSystem.Colors.info
        }
    }

    private func severityBadge(_ s: String) -> some View {
        let c = severityColor(s)
        return Text(s.capitalized)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(c)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(c.opacity(0.12), in: Capsule())
    }

    // MARK: - Live Status Card

    private func liveStatusCard(_ cards: [SwarmLiveCardState]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text("LIVE STATUS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }

            ForEach(cards, id: \.swarmId) { card in
                let cardAccent = statusAccent(card.status)
                let name = reviewCardName(card.swarmId)

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(cardAccent)
                        .frame(width: 2.5)
                        .padding(.vertical, 3)

                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(card.currentStepTitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textShimmer(active: card.status == .running)

                        if card.warningCount > 0 && card.status != .failed {
                            Text("⚠︎ \(card.warningCount)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.warning)
                        }

                        Spacer(minLength: 4)

                        if card.status == .running {
                            ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: card.status == .failed
                                ? "xmark.circle.fill"
                                : (card.warningCount > 0 ? "exclamationmark.triangle.fill"
                                    : (card.status == .completed ? "checkmark.circle.fill" : "circle")))
                                .font(.system(size: 9))
                                .foregroundStyle((card.warningCount > 0 && card.status != .failed)
                                    ? DesignSystem.Colors.warning.opacity(0.85)
                                    : cardAccent.opacity(0.8))
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 5)
                    .padding(.trailing, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                )
            }
        }
    }

    private func statusAccent(_ s: SwarmCardStatus) -> Color {
        switch s {
        case .running: return accent
        case .completed: return DesignSystem.Colors.success
        case .failed: return DesignSystem.Colors.error
        case .idle: return .secondary
        }
    }

    private func reviewCardName(_ swarmId: String) -> String {
        let id = swarmId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.lowercased().hasPrefix("review-") {
            let suffix = String(id.dropFirst("review-".count))
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                return "Review \(suffix)"
            }
        }
        if let dash = id.range(of: "-", options: .backwards) {
            let suffix = id[dash.upperBound...]
            if suffix.count >= 8, suffix.allSatisfy({ $0.isHexDigit }) {
                return String(id[..<dash.lowerBound]).capitalized
            }
        }
        return id.capitalized
    }

    // MARK: - Config Tab

    private var configTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if isTaskRunning {
                    Text("Configuration changes apply to the next review run.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                configCard(title: "Max Workers", icon: "person.3.fill") {
                    HStack {
                        Text("Concurrent workers")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Stepper(value: $codeReviewPartitions, in: 1...12) {
                            Text("\(codeReviewPartitions)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)
                        }
                        .fixedSize()
                    }
                    Text("The analysis LLM decides how many to spawn (up to this limit)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.quaternary)
                }

                configCard(title: "Max Rounds", icon: "arrow.triangle.2.circlepath") {
                    HStack {
                        Text("Autofix rounds")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Stepper(value: $codeReviewMaxRounds, in: 1...10) {
                            Text("\(codeReviewMaxRounds)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)
                        }
                        .fixedSize()
                    }
                }

                configCard(title: "Mode", icon: "eye") {
                    Toggle(isOn: $codeReviewAnalysisOnly) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Analysis Only")
                                .font(.system(size: 10.5, weight: .medium))
                            Text("Report findings without applying fixes")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                configCard(title: "Analysis Backend", icon: "cpu") {
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
                }

                if !codeReviewAnalysisOnly {
                    configCard(title: "Execution Backend", icon: "hammer") {
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
                    }
                }
            }
            .padding(12)
            .disabled(isTaskRunning)
            .opacity(isTaskRunning ? 0.78 : 1)
        }
    }

    private func configCard<C: View>(title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent.opacity(0.5))
                .frame(width: 2.5)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.6)
                }
                content()
            }
            .padding(.leading, 8)
            .padding(.vertical, 8)
            .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.4), lineWidth: 0.5)
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
                            .font(.system(size: 9))
                        Text("Activate Review Mode")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                    Text("Review mode active")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(accent)
            }

            Spacer()

            if coderMode == .codeReviewMultiSwarm && !isTaskRunning {
                Button {
                    onRunSlashCommand("""
                        Stage ONLY the files that were modified as part of this review session \
                        (do NOT use `git add -A` or `git add .`). \
                        Create a clean atomic commit with a descriptive commit message. \
                        Then push to the remote. Requirements: green build/tests before committing.
                        """)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 9))
                        Text("Commit & Push")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Commit fixes and push to remote")
            }

            if isTaskRunning && coderMode == .codeReviewMultiSwarm {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func runAgainstCommitReview() {
        let ref = againstCommitRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { return }
        let prompt = CodeReviewQuickCommands.againstPrompt(
            ref: ref,
            autofixEnabled: autofixEnabled,
            maxRounds: codeReviewMaxRounds
        )

        if coderMode != .codeReviewMultiSwarm {
            onSelectMode(.codeReviewMultiSwarm)
            Task { @MainActor in
                onRunSlashCommand(prompt)
            }
        } else {
            onRunSlashCommand(prompt)
        }
    }

    // MARK: - Slash Command Presets

    private struct SlashCommand: Identifiable {
        let id: String
        let slash: String
        let label: String
        let prompt: String
    }

    private var slashCommands: [SlashCommand] {
        CodeReviewQuickCommands.defaults.map {
            SlashCommand(id: $0.id, slash: $0.slash, label: $0.label, prompt: $0.prompt)
        }
    }

    // MARK: - Helpers

    private func isValidGitRef(_ ref: String) -> Bool {
        isValidGitRefFormat(ref)
    }
}

func isValidGitRefFormat(_ ref: String) -> Bool {
    let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    guard !trimmed.hasPrefix("-") else { return false }
    guard !trimmed.hasSuffix(".lock") else { return false }
    guard !trimmed.hasSuffix(".") else { return false }
    let invalidChars = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
    guard trimmed.unicodeScalars.allSatisfy({ !invalidChars.contains($0) }) else { return false }
    let forbidden = [":", "?", "*", "[", "\\", "@{"]
    for seq in forbidden { if trimmed.contains(seq) { return false } }
    return true
}

func latestReviewWorkerPlanBatch(in activities: [TaskActivity]) -> [TaskActivity] {
    guard let lastPlanIndex = activities.lastIndex(where: { $0.type == "review-worker-plan" }) else {
        return []
    }

    var firstPlanIndex = lastPlanIndex
    while firstPlanIndex > activities.startIndex {
        let previousIndex = activities.index(before: firstPlanIndex)
        guard activities[previousIndex].type == "review-worker-plan" else {
            break
        }
        firstPlanIndex = previousIndex
    }

    return Array(activities[firstPlanIndex...lastPlanIndex])
}

func scopedTaskActivitiesForConversation(
    _ activities: [TaskActivity],
    conversationId: UUID?
) -> [TaskActivity] {
    guard let conversationId else { return activities }
    let expected = conversationId.uuidString.lowercased()
    return activities.filter { activity in
        let tagged = (activity.payload["conversation_id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return tagged == expected
    }
}

func reviewCardBelongsToConversation(
    _ card: SwarmLiveCardState,
    conversationId: UUID?
) -> Bool {
    guard conversationId != nil else { return true }
    guard !card.recentEvents.isEmpty else { return false }
    return !scopedTaskActivitiesForConversation(card.recentEvents, conversationId: conversationId).isEmpty
}

func sortedReviewWorkerPlanActivitiesForDisplay(_ activities: [TaskActivity]) -> [TaskActivity] {
    activities.sorted { lhs, rhs in
        let lhsWorkerID = (lhs.payload["worker_id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsWorkerID = (rhs.payload["worker_id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lhsHasWorker = !lhsWorkerID.isEmpty
        let rhsHasWorker = !rhsWorkerID.isEmpty

        if lhsHasWorker && rhsHasWorker && lhsWorkerID != rhsWorkerID {
            return lhsWorkerID.localizedStandardCompare(rhsWorkerID) == .orderedAscending
        }
        if lhsHasWorker != rhsHasWorker {
            return lhsHasWorker
        }
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

func selectReviewWorkerActivities(from activities: [TaskActivity]) -> [TaskActivity] {
    guard !activities.isEmpty else { return [] }

    if let boundary = activities.lastIndex(where: { $0.type == "review-fix-round" }) {
        let after = Array(activities[(activities.index(after: boundary))...])
        let plansAfterBoundary = latestReviewWorkerPlanBatch(in: after)
        if !plansAfterBoundary.isEmpty {
            return plansAfterBoundary
        }

        let upToBoundary = Array(activities[...boundary])
        return latestReviewWorkerPlanBatch(in: upToBoundary)
    }

    return latestReviewWorkerPlanBatch(in: activities)
}
