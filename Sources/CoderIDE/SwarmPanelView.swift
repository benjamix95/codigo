import SwiftUI
import CoderEngine

// MARK: - Shared helpers (mirrored from SubagentChatCardView)

private func panelRoleDisplayName(from swarmId: String) -> String {
    let id = swarmId
    if let dashRange = id.range(of: "-", options: .backwards),
       id[dashRange.upperBound...].count <= 10,
       id[dashRange.upperBound...].allSatisfy({ $0.isHexDigit || $0.isLetter }) {
        return String(id[..<dashRange.lowerBound]).capitalized
    }
    return id.capitalized
}

private func panelStatusAccent(for status: SwarmCardStatus) -> Color {
    switch status {
    case .running: return DesignSystem.Colors.swarmColor
    case .completed: return DesignSystem.Colors.success
    case .failed: return DesignSystem.Colors.error
    case .idle: return .secondary
    }
}

// MARK: - Panel

struct SwarmPanelView: View {
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var swarmProgressStore: SwarmProgressStore
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var chatStore: ChatStore

    let conversationId: UUID?
    let isTaskRunning: Bool
    @Binding var selectedSwarmId: String?
    @Binding var swarmOrchestrator: String
    @Binding var swarmWorkerBackend: String
    let onClose: () -> Void
    let onOpenFile: (String) -> Void
    let onSyncSwarmProvider: () -> Void

    @State private var expandedCardIds: Set<String> = []
    @State private var expandedEventIds: Set<UUID> = []
    @State private var isFollowingLive = true
    @State private var isOrchestratorPopoverPresented = false
    @State private var isWorkerPopoverPresented = false

    private let topInteractiveInset: CGFloat = 22
    private let accent = DesignSystem.Colors.swarmColor

    private struct ProviderOption: Identifiable {
        let id: String
        let label: String
    }

    @State private var cachedCards: [SwarmLiveCardState] = []
    private var sortedCards: [SwarmLiveCardState] { cachedCards }
    private var runningCount: Int { cachedCards.filter { $0.status == .running }.count }
    private var failedCount: Int { cachedCards.filter { $0.status == .failed }.count }
    private var warningCount: Int { cachedCards.reduce(0) { $0 + max(0, $1.warningCount) } }
    private var completedCount: Int { cachedCards.filter { $0.status == .completed }.count }
    private var liveChangeCount: Int { taskActivityStore.swarmEventsReceivedCount }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)

            topBar
            Divider().opacity(0.3)

            if !sortedCards.isEmpty {
                swarmSelector
                Divider().opacity(0.2)
            }

            mainContent

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
        .onAppear {
            isFollowingLive = true
            refreshCachedCards()
            if selectedSwarmId == nil {
                selectedSwarmId = cachedCards.first(where: { $0.status == .running })?.swarmId
            }
        }
        .onChange(of: liveChangeCount) { _, _ in
            refreshCachedCards()
            if let sel = selectedSwarmId,
               !cachedCards.contains(where: { $0.swarmId == sel }) {
                selectedSwarmId = nil
            }
            if selectedSwarmId == nil,
               let firstRunning = cachedCards.first(where: { $0.status == .running }) {
                selectedSwarmId = firstRunning.swarmId
            }
        }
        .onChange(of: isTaskRunning) { _, v in if v { isFollowingLive = true } }
        .onChange(of: conversationId) { _, _ in
            isFollowingLive = true
            expandedCardIds.removeAll()
            expandedEventIds.removeAll()
        }
    }

    private func refreshCachedCards() {
        // taskActivityStore.swarmCardStates() is already sorted and cached.
        cachedCards = taskActivityStore.swarmCardStates()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "ant.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
            Text("Subagents")
                .font(.system(size: 13, weight: .semibold))

            if runningCount > 0 { badge("\(runningCount) running", accent) }
            if failedCount > 0 { badge("\(failedCount) failed", DesignSystem.Colors.error) }
            if warningCount > 0 { badge("\(warningCount) warnings", DesignSystem.Colors.warning) }
            if completedCount > 0 { badge("\(completedCount) done", DesignSystem.Colors.success) }

            Spacer()

            if isTaskRunning {
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

    // MARK: - Swarm Selector

    private var swarmSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    selectorPill("Overview", icon: "square.grid.2x2", isSelected: selectedSwarmId == nil) {
                        withAnimation(.snappy(duration: 0.2)) { selectedSwarmId = nil }
                    }
                    .id("sel-overview")

                    ForEach(sortedCards) { card in
                        selectorPill(
                            panelRoleDisplayName(from: card.swarmId),
                            isSelected: selectedSwarmId == card.swarmId
                        ) {
                            withAnimation(.snappy(duration: 0.2)) { selectedSwarmId = card.swarmId }
                        }
                        .id("sel-\(card.swarmId)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onChange(of: selectedSwarmId) { _, newId in
                let target = newId.map { "sel-\($0)" } ?? "sel-overview"
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func selectorPill(
        _ title: String,
        icon: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 8.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? accent : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if sortedCards.isEmpty {
            emptyState
        } else if let sid = selectedSwarmId, let card = sortedCards.first(where: { $0.swarmId == sid }) {
            detailView(for: card)
        } else {
            overviewList
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "ant.fill")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("No subagent activity")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Subagents will appear here when running")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: - Overview List

    private var overviewList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !swarmProgressStore.steps.isEmpty {
                        progressSection
                    }
                    ForEach(sortedCards) { card in
                        overviewCard(card)
                            .id("ov-\(card.swarmId)")
                    }
                }
                .padding(12)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { _ in isFollowingLive = false })
            .onChange(of: liveChangeCount) { _, _ in
                guard isFollowingLive,
                      let first = cachedCards.first(where: { $0.status == .running }) else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("ov-\(first.swarmId)", anchor: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
                Text("STEPS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }
            ForEach(swarmProgressStore.steps) { step in
                HStack(spacing: 6) {
                    Image(systemName: stepIcon(step))
                        .font(.system(size: 10))
                        .foregroundStyle(stepColor(step))
                    Text(step.name)
                        .font(.system(size: 11, weight: step.status == .inProgress ? .medium : .regular))
                        .foregroundStyle(step.status == .completed ? .tertiary : .primary)
                        .strikethrough(step.status == .completed)
                        .lineLimit(1)
                        .textShimmer(active: step.status == .inProgress)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
        )
    }

    // MARK: - Overview Card (Minimal dark card)

    @ViewBuilder
    private func overviewCard(_ card: SwarmLiveCardState) -> some View {
        let title: String = {
            let raw = card.currentStepTitle
            if raw.isEmpty || raw == "Awaiting events" {
                return panelRoleDisplayName(from: card.swarmId)
            }
            return raw
        }()

        let subtitle: String = {
            if card.status == .running {
                return liveSubtitle(for: card) ?? "Planning next moves"
            }
            if card.status == .completed { return card.warningCount > 0 ? "Done with warnings" : "Done" }
            if card.status == .failed { return "Failed" }
            if card.warningCount > 0 { return "Warnings" }
            return "Idle"
        }()

        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.6))
                .lineLimit(1)
                .textShimmer(active: card.status == .running)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) { selectedSwarmId = card.swarmId }
        }
    }

    // MARK: - Detail View

    private func detailView(for card: SwarmLiveCardState) -> some View {
        let cardAccent = panelStatusAccent(for: card.status)
        let name = panelRoleDisplayName(from: card.swarmId)

        let headerTitle: String = {
            let raw = card.currentStepTitle
            if raw.isEmpty || raw == "Awaiting events" { return name }
            return raw
        }()

        let headerSubtitle: String = {
            if card.status == .running {
                return liveSubtitle(for: card) ?? "Planning next moves"
            }
            if card.status == .completed { return card.warningCount > 0 ? "Done with warnings" : "Done" }
            if card.status == .failed { return "Failed" }
            if card.warningCount > 0 { return "Warnings" }
            return "Idle"
        }()

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selectedSwarmId = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .semibold))
                            Text("All Agents")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(headerTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.7))
                            .lineLimit(2)

                        Text(headerSubtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .lineLimit(1)
                            .textShimmer(active: card.status == .running)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )

                    if !card.currentDetail.isEmpty {
                        Text(card.currentDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
                            )
                    }

                    let events = card.recentEvents
                    if !events.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("EVENTS")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                    .tracking(0.8)
                                Spacer()
                                Text("\(events.count)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.quaternary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                            }

                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(events) { activity in
                                    detailEventRow(activity, accent: cardAccent)
                                        .id("det-\(activity.id)")
                                }
                            }
                        }
                    }

                    if let summary = card.summary {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SUMMARY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .tracking(0.8)
                            Text(summary)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
                        )
                    }
                }
                .padding(14)
            }
            .onChange(of: card.recentEvents.count) { _, _ in
                if isFollowingLive, let last = card.recentEvents.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("det-\(last.id)", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail Event Row

    @ViewBuilder
    private func detailEventRow(_ activity: TaskActivity, accent: Color) -> some View {
        let isExp = expandedEventIds.contains(activity.id)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(activity.isRunning ? accent : .secondary.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text(activity.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(isExp ? nil : 2)
                    .textShimmer(active: activity.isRunning)
                Spacer()
                Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }

            if let detail = activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExp ? nil : 2)
            }

            if let cmd = activity.payload["command"], !cmd.isEmpty {
                Text("$ \(cmd)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExp ? nil : 2)
            } else if let path = activity.payload["path"] ?? activity.payload["file"], !path.isEmpty {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if hasRawDetail(activity) {
                Button(isExp ? "Hide details" : "Show details") {
                    if isExp { expandedEventIds.remove(activity.id) }
                    else { expandedEventIds.insert(activity.id) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }

            if isExp {
                let raw = rawDetail(for: activity)
                if !raw.isEmpty {
                    Text(raw)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                        )
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("\(sortedCards.count) agents")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                if isTaskRunning {
                    let totalOps = sortedCards.reduce(0) { $0 + $1.activeOpsCount }
                    if totalOps > 0 {
                        Text("·").foregroundStyle(.quaternary)
                        Text("\(totalOps) active ops")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accent)
                    }
                }

                Spacer()

                if !isFollowingLive && isTaskRunning {
                    Button("Follow Live") { isFollowingLive = true }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent)
                        .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                orchestratorPicker
                workerPicker
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Provider Pickers

    private var orchestratorLabel: String {
        switch swarmOrchestrator {
        case "auto": return "Auto"
        case "codex": return "Codex"
        case "claude": return "Claude"
        case "gemini": return "Gemini"
        case "anthropic-api": return "Anthropic"
        case "google-api": return "Google"
        case "openrouter-api": return "OpenRouter"
        case "minimax-api": return "MiniMax"
        case "grok-api": return "Grok"
        default: return "OpenAI"
        }
    }

    private var orchestratorPicker: some View {
        Button {
            isWorkerPopoverPresented = false
            isOrchestratorPopoverPresented.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "cpu").font(.system(size: 8))
                Text("Orch: \(orchestratorLabel)").font(.system(size: 10))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isOrchestratorPopoverPresented, arrowEdge: .bottom) {
            providerPopover(
                title: "Orchestrator Backend",
                options: orchestratorOptions,
                selectedId: swarmOrchestrator
            ) { id in
                swarmOrchestrator = id
                onSyncSwarmProvider()
                isOrchestratorPopoverPresented = false
            }
        }
    }

    private var workerLabel: String {
        switch swarmWorkerBackend {
        case "auto": return "Auto"
        case "claude": return "Claude"
        case "gemini": return "Gemini"
        case "openai-api", "openai": return "OpenAI"
        case "anthropic-api": return "Anthropic"
        case "google-api": return "Google"
        case "openrouter-api", "openrouter": return "OpenRouter"
        case "minimax-api": return "MiniMax"
        case "grok-api": return "Grok"
        default: return "Codex"
        }
    }

    private var workerPicker: some View {
        Button {
            isOrchestratorPopoverPresented = false
            isWorkerPopoverPresented.toggle()
        } label: {
            HStack(spacing: 3) {
                Text("Worker: \(workerLabel)").font(.system(size: 10))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isWorkerPopoverPresented, arrowEdge: .bottom) {
            providerPopover(
                title: "Worker Backend",
                options: workerOptions,
                selectedId: swarmWorkerBackend
            ) { id in
                swarmWorkerBackend = id
                onSyncSwarmProvider()
                isWorkerPopoverPresented = false
            }
        }
    }

    private var orchestratorOptions: [ProviderOption] {
        [
            .init(id: "auto", label: "Auto (same as Agent)"),
            .init(id: "openai", label: "OpenAI API"),
            .init(id: "anthropic-api", label: "Anthropic API"),
            .init(id: "google-api", label: "Google API"),
            .init(id: "openrouter-api", label: "OpenRouter"),
            .init(id: "minimax-api", label: "MiniMax API"),
            .init(id: "grok-api", label: "Grok API"),
            .init(id: "codex", label: "Codex CLI"),
            .init(id: "claude", label: "Claude Code"),
            .init(id: "gemini", label: "Gemini CLI"),
        ]
    }

    private var workerOptions: [ProviderOption] {
        [
            .init(id: "auto", label: "Auto (same as Agent)"),
            .init(id: "openai-api", label: "OpenAI API"),
            .init(id: "anthropic-api", label: "Anthropic API"),
            .init(id: "google-api", label: "Google API"),
            .init(id: "openrouter-api", label: "OpenRouter"),
            .init(id: "minimax-api", label: "MiniMax API"),
            .init(id: "grok-api", label: "Grok API"),
            .init(id: "codex", label: "Codex CLI"),
            .init(id: "claude", label: "Claude Code"),
            .init(id: "gemini", label: "Gemini CLI"),
        ]
    }

    private func providerPopover(
        title: String,
        options: [ProviderOption],
        selectedId: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(options) { option in
                        Button {
                            onSelect(option.id)
                        } label: {
                            HStack(spacing: 8) {
                                Text(option.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                if selectedId == option.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(accent)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selectedId == option.id ? accent.opacity(0.12) : Color.clear)
                        )
                    }
                }
            }
            .frame(width: 240)
            .frame(maxHeight: 260)
        }
        .padding(10)
    }

    // MARK: - Helpers

    private func stepIcon(_ step: SwarmStep) -> String {
        switch step.status {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "arrow.right.circle.fill"
        case .pending: return "circle"
        }
    }

    private func stepColor(_ step: SwarmStep) -> Color {
        switch step.status {
        case .completed: return DesignSystem.Colors.success
        case .inProgress: return DesignSystem.Colors.warning
        case .pending: return DesignSystem.Colors.borderAccent
        }
    }

    private func hasRawDetail(_ activity: TaskActivity) -> Bool {
        !(activity.payload["output"] ?? "").isEmpty ||
        !(activity.payload["stderr"] ?? "").isEmpty ||
        !(activity.payload["cwd"] ?? "").isEmpty ||
        !(activity.payload["diffPreview"] ?? "").isEmpty
    }

    private func liveSubtitle(for card: SwarmLiveCardState) -> String? {
        let last = card.recentEvents.last
        let candidates: [String?] = [
            card.currentDetail,
            last?.detail,
            last?.payload["detail"],
            last?.payload["query"],
            last?.payload["path"],
            last?.payload["command"],
            last?.payload["tool"],
            last?.payload["mcp_tool"],
        ]
        for candidate in candidates {
            let text = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let lower = text.lowercased()
            if lower == "started" || lower == "running" || lower == "in_progress" || lower == "pending" {
                continue
            }
            return String(text.prefix(120))
        }
        return nil
    }

    private func rawDetail(for activity: TaskActivity) -> String {
        var lines: [String] = []
        if let cwd = activity.payload["cwd"], !cwd.isEmpty { lines.append("cwd: \(cwd)") }
        if let output = activity.payload["output"], !output.isEmpty { lines.append(String(output.prefix(4096))) }
        if let stderr = activity.payload["stderr"], !stderr.isEmpty { lines.append("stderr:\n\(String(stderr.prefix(4096)))") }
        if let diff = activity.payload["diffPreview"], !diff.isEmpty { lines.append("diff:\n\(String(diff.prefix(2048)))") }
        return lines.joined(separator: "\n\n")
    }
}
