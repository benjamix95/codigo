import SwiftUI
import AppKit
import CoderEngine

/// Universal login sheet for any CLI provider (Codex, Claude, Gemini).
/// Replaces the Codex-specific `CodexLoginView` with a provider-agnostic flow.
struct CLIAccountLoginSheet: View {
    @Environment(\.dismiss) var dismiss

    let account: CLIAccount
    let providerPath: String?
    var onDismiss: (() -> Void)?

    @StateObject private var coordinator = CLIAccountLoginCoordinator()
    @State private var apiKey = ""
    @State private var phase: LoginPhase = .options
    @State private var copiedURLHint = false
    @State private var authCodeInput = ""
    @State private var authCodeHint = ""
    @State private var deviceCodeCopied = false
    @State private var availableBrowsers: [BrowserApp] = []

    private enum LoginPhase {
        case options
        case polling(message: String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch phase {
            case .options:
                optionsView
            case .polling(let message):
                pollingView(message: message)
            }
        }
        .frame(width: 400)
        .onAppear {
            refreshAvailableBrowsers()
        }
    }
}
