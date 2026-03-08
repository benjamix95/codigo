import CoderEngine
import SwiftUI

extension ModeControlsBarView {
    // MARK: - Codex Model Picker
    var codexModelPicker: some View {
        Menu {
            Button {
                codexModelOverride = ""
                onSyncCodexProvider()
            } label: {
                HStack {
                    Text("Default (from config)")
                    if codexModelOverride.isEmpty { Image(systemName: "checkmark") }
                }
            }
            if !codexModels.isEmpty {
                Divider()
                ForEach(codexModels, id: \.slug) { m in
                    Button {
                        codexModelOverride = m.slug
                        onSyncCodexProvider()
                    } label: {
                        HStack {
                            Text(m.displayName)
                            if codexModelOverride == m.slug { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if CodexFastModeStore.currentValue() {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(codexModelLabel).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    var codexModelLabel: String {
        codexModelOverride.isEmpty
            ? "Default"
            : (codexModels.first(where: { $0.slug == codexModelOverride })?.displayName
                ?? codexModelOverride)
    }
}
