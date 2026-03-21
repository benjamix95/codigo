import SwiftUI

extension PlanPanelView {
    var isPlanFullyBuilt: Bool {
        // Don't show "Built" during active building phase — wait until phase
        // transitions to readyToBuild/idle to avoid brief UI flicker.
        guard planFlowPhase != .building else { return false }
        let canonical = canonicalPlanTodos
        guard !canonical.isEmpty else {
            return false
        }
        return canonical.allSatisfy { $0.status == .done } && !isCurrentConversationLoading
    }

    var isBuildEnabledByPhase: Bool {
        isPlanBuildEnabled(
            phase: planFlowPhase,
            hasBuildChoice: resolvedBuildChoice != nil,
            allowIdleRebuild: resolvedBuildChoice != nil,
            providerExecutionCapable: isActiveProviderExecutionCapable
        )
    }

    var shouldShowCanonicalTodos: Bool {
        switch planFlowPhase {
        case .readyToBuild, .building:
            return true
        case .idle, .proposalReady:
            return !canonicalPlanTodos.isEmpty
        default:
            return false
        }
    }

    var isPreBuildPlanState: Bool {
        if case .awaitingClarification = planningState {
            return true
        }
        switch planFlowPhase {
        case .analyzing, .questioning, .generating:
            return true
        case .proposalReady, .idle, .readyToBuild, .building:
            return false
        }
    }

    var shouldShowPlanDetailsSection: Bool {
        !isPreBuildPlanState
    }

    var buildDisabledReason: String? {
        planBuildDisabledReason(
            phase: planFlowPhase,
            hasBuildChoice: resolvedBuildChoice != nil,
            providerExecutionCapable: isActiveProviderExecutionCapable
        )
    }

    var resolvedBuildChoice: (text: String, isFallback: Bool)? {
        resolveBuildChoice()
    }

    var phaseHint: String? {
        switch planFlowPhase {
        case .idle:
            return buildHint ?? buildDisabledReason
        case .analyzing:
            return "Analyzing..."
        case .questioning:
            return "Awaiting answers"
        case .generating:
            return "Generating..."
        case .proposalReady:
            return buildDisabledReason ?? "Select an option"
        case .readyToBuild:
            return buildDisabledReason ?? "Ready"
        case .building:
            return "Building..."
        }
    }

    var buildButton: some View {
        let fullyBuilt = isPlanFullyBuilt
        return Group {
            if fullyBuilt {
                Menu {
                    Button {
                        performBuild()
                    } label: {
                        Label("Run again", systemImage: "arrow.clockwise")
                    }
                    Button {
                        downloadCurrentPlan()
                    } label: {
                        Label("Download .md", systemImage: "arrow.down.doc")
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                        Text("Built")
                            .font(.system(size: 10, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        DesignSystem.Colors.planGradient,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Plan completed. Click to execute again (⌘⏎)")
                .disabled(!isBuildEnabledByPhase)
            } else {
                Button {
                    if isCurrentConversationLoading {
                        onStop()
                        buildHint = "Build interrupted"
                    } else {
                        performBuild()
                    }
                } label: {
                    HStack(spacing: 3) {
                        if isCurrentConversationLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        }
                        Image(systemName: isCurrentConversationLoading ? "stop.fill" : "play.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(isCurrentConversationLoading ? "Stop" : "Build")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        DesignSystem.Colors.planGradient,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .opacity(isCurrentConversationLoading ? 0.8 : 1)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(PlanBuildButtonStyle())
                .help(isCurrentConversationLoading ? "Stop build (⌘⏎)" : (buildDisabledReason ?? "Run plan (⌘⏎)"))
                .disabled(!isBuildEnabledByPhase && !isCurrentConversationLoading)
            }
        }
    }

    func performBuild() {
        guard isBuildEnabledByPhase else {
            buildHint = buildDisabledReason ?? phaseHint ?? "Build unavailable."
            return
        }
        guard let choice = resolvedBuildChoice?.text else {
            buildHint = "No option selected."
            return
        }
        buildHint = "Build started..."
        let allowIdleRebuild = shouldAllowIdleRebuildFromMainBuildAction(
            phase: planFlowPhase,
            hasBuildChoice: resolvedBuildChoice != nil
        )
        onBuild(choice, planProviderId, allowIdleRebuild)
    }

    // MARK: - Bottom Bar

    func bottomBar(canonicalTodos: [TodoItem]) -> some View {
        HStack(spacing: 6) {
            let total = canonicalTodos.count
            let done = canonicalTodos.filter { $0.status == .done }.count
            if total > 0 {
                Text("\(done)/\(total)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary.opacity(0.06))
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(planColor.opacity(0.5))
                            .frame(width: geo.size.width * CGFloat(done) / CGFloat(max(total, 1)))
                    }
                }
                .frame(maxWidth: 50, maxHeight: 2)
            }
            Spacer()
            if planFlowPhase == .building, isCurrentConversationLoading {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                    Text("Building")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}
