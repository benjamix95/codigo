import Foundation
import AppKit
import CoderEngine

@MainActor
final class CLIAccountLoginCoordinator: ObservableObject {
    enum LoginMethod: String, CaseIterable, Identifiable {
        case browserOAuth
        case deviceCode
        case apiKey

        var id: String { rawValue }
        var title: String {
            switch self {
            case .browserOAuth: return "Browser OAuth"
            case .deviceCode: return "Device code"
            case .apiKey: return "API key"
            }
        }
    }

    @Published var isRunningByAccount: [UUID: Bool] = [:]
    @Published var statusByAccount: [UUID: String] = [:]
    @Published var authURLByAccount: [UUID: URL] = [:]
    @Published var lastOutputByAccount: [UUID: String] = [:]
    @Published var awaitingInputByAccount: [UUID: Bool] = [:]
    @Published var deviceCodeByAccount: [UUID: String] = [:]

    var loginProcesses: [UUID: Process] = [:]
    var loginInputPipes: [UUID: Pipe] = [:]
    var pendingBrowserOpenByAccount: [UUID: URL?] = [:]

    func startLogin(account: CLIAccount, providerPath: String?, method: LoginMethod, apiKey: String?) {
        startLoginFlow(account: account, providerPath: providerPath, method: method, apiKey: apiKey)
    }

    func pollLoginStatus(account: CLIAccount, providerPath: String?) async {
        await pollLoginStatusFlow(account: account, providerPath: providerPath)
    }

    func cancelLogin(accountId: UUID) {
        cancelLoginFlow(accountId: accountId)
    }

    func setSelectedBrowser(_ browserAppURL: URL?, forAccount accountId: UUID) {
        pendingBrowserOpenByAccount[accountId] = .some(browserAppURL)
    }

    @discardableResult
    func submitInteractiveInput(accountId: UUID, text: String) -> Bool {
        return submitInteractiveInputFlow(accountId: accountId, text: text)
    }

    func disconnect(account: CLIAccount) {
        disconnectFlow(account: account)
    }
}
