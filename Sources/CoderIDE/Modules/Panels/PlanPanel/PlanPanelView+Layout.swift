import SwiftUI

extension PlanPanelView {
    // MARK: - Fixed Toolbar (Cursor-style)

    var fixedToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                breadcrumb

                if let hint = phaseHint {
                    Text(hint)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                providerPicker
                buildButton

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close panel")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Breadcrumb

    var breadcrumb: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(planColor.opacity(0.7))
            Text(planFileName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    var planFileName: String {
        let selectedHistoryTitle: String? = {
            guard !shouldPreferLivePlanBoardOverHistory(
                phase: planFlowPhase,
                planningState: planningState
            ) else {
                return nil
            }
            return selectedHistoryEntryForConversation()?.title
        }()
        let boardGoal = chatStore.planBoard(for: conversationId)?
            .goal
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredPlanTitle = normalizedPlanText(selectedHistoryTitle ?? boardGoal ?? "")
        let conversationTitle = chatStore.conversation(for: conversationId)?.title
        return makePlanFileName(
            preferredPlanTitle: preferredPlanTitle.isEmpty ? nil : preferredPlanTitle,
            fallbackConversationTitle: conversationTitle
        )
    }

    // MARK: - Provider Picker

    var providerPicker: some View {
        let allowedProviders = providerRegistry.providers.filter {
            isPlanExecutionProviderIdAllowed($0.id)
        }

        return Menu {
            Button {
                planProviderId = nil
            } label: {
                HStack {
                    Text("Auto (same as Agent)")
                    if planProviderId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            if allowedProviders.isEmpty {
                Text("No providers available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(allowedProviders.enumerated()), id: \.element.id) { _, provider in
                    let isAuth = providerAuthCache[provider.id] == true
                    Button {
                        planProviderId = provider.id
                    } label: {
                        HStack {
                            Text(provider.displayName)
                            if !isAuth {
                                Text("Not Auth")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            } else if !ProviderSupport.isPlanBuildExecutionCapableProvider(
                                id: provider.id,
                                registry: providerRegistry
                            ) {
                                Text("Not executable")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                            if planProviderId == provider.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(
                        !isAuth
                            || !ProviderSupport.isPlanBuildExecutionCapableProvider(
                                id: provider.id,
                                registry: providerRegistry
                            )
                    )
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(activeProviderLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.quaternary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    var activeProviderId: String {
        if let override = planProviderId,
           isPlanExecutionProviderIdAllowed(override),
           ProviderSupport.isPlanBuildExecutionCapableProvider(id: override, registry: providerRegistry),
           providerAuthCache[override] == true {
            return override
        }
        if let selected = providerRegistry.selectedProviderId,
           isPlanExecutionProviderIdAllowed(selected),
           ProviderSupport.isPlanBuildExecutionCapableProvider(id: selected, registry: providerRegistry),
           providerAuthCache[selected] == true {
            return selected
        }
        if let firstAuthenticated = providerRegistry.providers.first(where: {
            isPlanExecutionProviderIdAllowed($0.id)
                && ProviderSupport.isPlanBuildExecutionCapableProvider(id: $0.id, registry: providerRegistry)
                && providerAuthCache[$0.id] == true
        }) {
            return firstAuthenticated.id
        }
        return providerRegistry.selectedProviderId ?? providerRegistry.providers.first?.id ?? ""
    }

    var activeProviderLabel: String {
        if planProviderId == nil {
            return "Auto"
        }
        let targetId = activeProviderId
        if let p = providerRegistry.providers.first(where: { $0.id == targetId }) {
            return p.displayName
        }
        return "Provider"
    }

    var isActiveProviderExecutionCapable: Bool {
        guard isPlanExecutionProviderIdAllowed(activeProviderId) else { return false }
        guard providerAuthCache[activeProviderId] == true else { return false }
        return ProviderSupport.isPlanBuildExecutionCapableProvider(
            id: activeProviderId,
            registry: providerRegistry
        )
    }

    func refreshProviderAuthCache() {
        let ids = providerRegistry.providers
            .filter { isPlanExecutionProviderIdAllowed($0.id) }
            .map(\.id)
        guard !ids.isEmpty else {
            providerAuthCache = [:]
            return
        }
        var cache: [String: Bool] = [:]
        for id in ids {
            cache[id] = providerRegistry.provider(for: id)?.isAuthenticated() ?? false
        }
        providerAuthCache = cache
    }

    @ViewBuilder
    var executionCapabilityBadge: some View {
        if !isActiveProviderExecutionCapable {
            Circle()
                .fill(Color.orange)
                .frame(width: 5, height: 5)
                .help("Not executable")
        }
    }
}
