import CoderEngine
import SwiftUI

extension ModeControlsBarView {
    // MARK: - Claude Model Picker
    var claudeModelPicker: some View {
        Menu {
            ForEach(ClaudeModelsCache.loadModels(), id: \.slug) { model in
                Button {
                    claudeModel = model.slug
                    onSyncClaudeProvider()
                } label: {
                    HStack {
                        Text(model.displayName)
                        if claudeModel == model.slug { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(ClaudeModelsCache.displayName(for: claudeModel)).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Gemini Model Picker
    var geminiModelPicker: some View {
        Menu {
            Button {
                geminiModelOverride = ""
                onSyncGeminiProvider()
            } label: {
                HStack {
                    Text("Default (auto)")
                    if geminiModelOverride.isEmpty { Image(systemName: "checkmark") }
                }
            }
            if !geminiModels.isEmpty {
                Divider()
                ForEach(geminiModels, id: \.slug) { m in
                    Button {
                        geminiModelOverride = m.slug
                        onSyncGeminiProvider()
                    } label: {
                        HStack {
                            Text(m.displayName)
                            if geminiModelOverride == m.slug { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(geminiModelLabel).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    var geminiModelLabel: String {
        geminiModelOverride.isEmpty
            ? "Default"
            : (geminiModels.first(where: { $0.slug == geminiModelOverride })?.displayName
                ?? geminiModelOverride)
    }

    // MARK: - OpenRouter Model Picker
    var openRouterModelPicker: some View {
        Menu {
            if !openRouterPopularModels.isEmpty {
                Section("Popular") {
                    ForEach(openRouterPopularModels, id: \.self) { model in
                        Button {
                            openrouterModel = model
                            onSyncOpenRouterProvider()
                        } label: {
                            HStack {
                                Text(model)
                                if openrouterModel == model { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            if !openRouterFreeModels.isEmpty {
                Section("Free") {
                    ForEach(openRouterFreeModels, id: \.self) { model in
                        Button {
                            openrouterModel = model
                            onSyncOpenRouterProvider()
                        } label: {
                            HStack {
                                Text(model)
                                Text("FREE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                                if openrouterModel == model { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(openRouterModelLabel).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    var openRouterModelLabel: String {
        let trimmed = openrouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "OpenRouter Model"
        }
        let display = trimmed.replacingOccurrences(of: ":free", with: "")
        if trimmed.hasSuffix(":free") {
            return "\(display) · FREE"
        }
        return display
    }
}
