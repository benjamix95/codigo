import Foundation
import SwiftUI
import CoderEngine

extension UsageFooterView {
    private static let codexGPT54DefaultWindow = 272_000

    var effectiveContextModel: String {
        let providerId = effectiveProviderId ?? ""
        switch providerId {
        case "codex-cli":
            return codexModelOverride.isEmpty ? "gpt-5-codex" : codexModelOverride
        case "claude-cli":
            return claudeModel
        case "gemini-cli":
            return geminiModelOverride.isEmpty ? googleModelSetting : geminiModelOverride
        case "openai-api":
            return openaiModelSetting
        case "anthropic-api":
            return anthropicModelSetting
        case "google-api":
            return googleModelSetting
        case "openrouter-api":
            return normalizeOpenRouterModelId(openrouterModelSetting)
        case "minimax-api":
            return minimaxModelSetting
        case "grok-api":
            return grokModelSetting
        default:
            if providerId.contains("claude") { return claudeModel }
            return openaiModelSetting.isEmpty ? openaiModel : openaiModelSetting
        }
    }

    var contextEstimateConversationSignature: String {
        guard let conversation = chatStore.conversation(for: selectedConversationId) else {
            return "no-conversation"
        }
        let lastMessageId = conversation.messages.last?.id.uuidString ?? "none"
        let memoryTimestamp = conversation.contextMemoryGeneratedAt?.timeIntervalSince1970 ?? 0
        let memoryCount = conversation.contextMemorySourceMessageCount ?? -1
        let realTokens = conversation.lastInputTokens ?? 0
        return [
            conversation.id.uuidString,
            "\(conversation.messages.count)",
            lastMessageId,
            "\(Int(memoryTimestamp))",
            "\(memoryCount)",
            "\(realTokens)",
        ].joined(separator: "|")
    }

    func resolvedContextWindowSize(providerId: String?, model: String) -> Int {
        let normalized = model.lowercased()
        if providerId == "codex-cli", let configuredWindow = configuredCodexContextWindow() {
            return configuredWindow
        }
        if normalized.contains("gemini") {
            return 1_048_576
        }
        if providerId == "codex-cli", normalized == "gpt-5.4" {
            return Self.codexGPT54DefaultWindow
        }
        if normalized.contains("gpt-5") || normalized.contains("codex") {
            return 200_000
        }
        if normalized.contains("claude") {
            return 200_000
        }
        return ContextEstimator.contextSize(for: providerId, model: model)
    }

    private func configuredCodexContextWindow() -> Int? {
        let codexHome: String
        if let activeCodexAccount = activeAccount(for: .codex) {
            codexHome = activeCodexAccount.profilePath
        } else {
            codexHome = CodexConfigLoader.codexHome
        }

        let path = CodexConfigLoader.configPath(forCodexHome: codexHome)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        for line in content.components(separatedBy: CharacterSet.newlines) {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.hasPrefix("#"),
                  trimmed.hasPrefix("model_context_window"),
                  let equalIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let rawValue = trimmed[trimmed.index(after: equalIndex)...]
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if let parsed = Int(rawValue), parsed > 0 {
                return parsed
            }
        }

        return nil
    }
}
