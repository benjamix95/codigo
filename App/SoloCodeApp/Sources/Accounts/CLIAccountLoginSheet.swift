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

    @StateObject var coordinator = CLIAccountLoginCoordinator()
    @State var apiKey = ""
    @State var phase: LoginPhase = .options
    @State var copiedURLHint = false
    @State var authCodeInput = ""
    @State var authCodeHint = ""
    @State var deviceCodeCopied = false
    @State var availableBrowsers: [BrowserApp] = []

    enum LoginPhase {
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

    // MARK: - Header
    var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(providerColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: providerIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(providerColor)
            }

            Text("Sign in to \(account.provider.displayName)")
                .font(.title3.weight(.semibold))

            Text(account.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    func refreshAvailableBrowsers() {
        guard let probeURL = URL(string: "https://claude.ai") else { return }
        let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL)
        let defaultBundleId = defaultAppURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)

        var seen: Set<String> = []
        var detected: [BrowserApp] = []
        for appURL in appURLs {
            guard let bundle = Bundle(url: appURL) else { continue }
            let bundleId = bundle.bundleIdentifier ?? appURL.path
            guard seen.insert(bundleId).inserted else { continue }
            let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            detected.append(
                BrowserApp(
                    id: bundleId,
                    name: displayName,
                    url: appURL,
                    isDefault: bundleId == defaultBundleId
                )
            )
        }
        availableBrowsers = detected.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
