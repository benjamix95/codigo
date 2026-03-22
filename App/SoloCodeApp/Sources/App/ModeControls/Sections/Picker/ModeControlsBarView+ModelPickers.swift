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

    // MARK: - OpenAI Model Picker
    var openAIModelPicker: some View {
        let models = openAIModelPickerStore.models
        return Menu {
            ForEach(models, id: \.self) { model in
                Button {
                    openaiModel = model
                } label: {
                    HStack {
                        Text(model)
                        if OpenAIAPIProvider.isReasoningModel(model) {
                            Text("Reasoning").font(.system(size: 9, weight: .bold)).foregroundStyle(.blue)
                        }
                        if openaiModel == model { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(openaiModel).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Kilo Model Picker
    var kiloModelPicker: some View {
        Menu {
            Button {
                kiloModel = ""
                onSyncKiloProvider()
            } label: {
                HStack {
                    Text("Auto")
                    if kiloModel.isEmpty { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(kiloModels, id: \.self) { model in
                Button {
                    kiloModel = model
                    onSyncKiloProvider()
                } label: {
                    HStack {
                        Text(model)
                        if model.hasSuffix(":free") {
                            Text("FREE").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                        }
                        if kiloModel == model { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(kiloModel.isEmpty ? "Auto" : kiloModel).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - OpenRouter Model Picker
    var openRouterModelPicker: some View {
        let freeModels = openRouterModelPickerStore.freeModels
        let allModels = openRouterModelPickerStore.allModels
        let popularSet = Set(openRouterPopularModels)
        let freeSet = Set(freeModels)
        let remainingModels = allModels.filter { !popularSet.contains($0) && !freeSet.contains($0) }

        return Menu {
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
            if !freeModels.isEmpty {
                Section("Free") {
                    ForEach(freeModels, id: \.self) { model in
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
            if !remainingModels.isEmpty {
                Section("All") {
                    ForEach(remainingModels, id: \.self) { model in
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
        } label: {
            HStack(spacing: 4) {
                Text(openRouterModelLabel).font(.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .task {
            openRouterModelPickerStore.loadIfNeeded()
        }
    }

    var openRouterModelLabel: String {
        let trimmed = openrouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "OpenRouter Model"
        }
        let display = trimmed.replacingOccurrences(of: ":free", with: "")
        if trimmed.hasSuffix(":free") || openRouterModelPickerStore.isFree(trimmed) {
            return "\(display) · FREE"
        }
        return display
    }
}
