import CoderEngine
import SwiftUI

extension ModeControlsBarView {
    // MARK: - Provider Picker
    func providerPickerView(showLabel: Bool) -> some View {
        let realProviders = providerRegistry.providers
            .filter { ProviderSupport.isUserSelectableRealProvider(id: $0.id) }
        return Menu {
            ForEach(realProviders, id: \.id) { provider in
                Button {
                    onUserSelectedProvider()
                    providerRegistry.selectedProviderId = provider.id
                    chatStore.updatePreferredProvider(
                        conversationId: conversationId, providerId: provider.id
                    )
                } label: {
                    HStack {
                        Text(provider.displayName)
                        if providerRegistry.selectedProviderId == provider.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.caption2)
                if showLabel {
                    Text(providerLabel).font(.caption).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    var providerLabel: String {
        if let id = providerRegistry.selectedProviderId,
            ProviderSupport.isUserSelectableRealProvider(id: id),
            let p = providerRegistry.providers.first(where: { $0.id == id })
        {
            return p.displayName
        }
        if let fallback = providerRegistry.providers.first(where: {
            ProviderSupport.isUserSelectableRealProvider(id: $0.id)
        }) {
            return fallback.displayName
        }
        return "No provider"
    }
}
