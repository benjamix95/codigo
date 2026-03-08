import SwiftUI

extension ChatPanelView {
    internal func handleComposerSend() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"),
              trimmed.lowercased() == "/fast",
              providerRegistry.selectedProviderId == "codex-cli"
        else {
            sendMessage()
            return
        }

        handleComposerQuickCommand("/fast", runImmediately: false)
    }

    internal func handleComposerQuickCommand(_ text: String, runImmediately: Bool) {
        let slash = text
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        guard slash == "/fast", providerRegistry.selectedProviderId == "codex-cli" else {
            inputText = applyComposerCodeReviewModesIfNeeded(to: text)
            isInputFocused = true
            if runImmediately {
                sendMessage()
            }
            return
        }

        let nextValue = !CodexFastModeStore.currentValue()
        CodexFastModeStore.persist(nextValue)
        syncCodexProvider()
        inputText = ""
        isInputFocused = true
    }
}
