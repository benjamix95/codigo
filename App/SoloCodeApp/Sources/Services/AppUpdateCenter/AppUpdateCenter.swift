import Foundation
import OSLog
import SwiftUI

@MainActor
final class AppUpdateCenter: ObservableObject {
    // MARK: - Configuration

    nonisolated static let defaultManifestURL = "https://raw.githubusercontent.com/benjamix95/solocode/main/docs/update/manifest.json"
    static let checkInterval: TimeInterval = 60 * 60 * 24

    @Published var state: UpdateState = .idle
    @Published var availableUpdate: AppUpdateManifest?
    @Published var lastCheckedAt: Date?
    @Published var lastError: String?

    let logger = Logger(subsystem: "com.solocode.app", category: "update")
    let userDefaults: UserDefaults
    let urlSession: URLSession
    private let currentVersionProvider: @MainActor () -> String
    private let currentBuildProvider: @MainActor () -> String

    init(
        userDefaults: UserDefaults = .standard,
        urlSession: URLSession = .shared,
        currentVersionProvider: @escaping @MainActor () -> String = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        },
        currentBuildProvider: @escaping @MainActor () -> String = {
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        }
    ) {
        self.userDefaults = userDefaults
        self.urlSession = urlSession
        self.currentVersionProvider = currentVersionProvider
        self.currentBuildProvider = currentBuildProvider
        self.lastCheckedAt = userDefaults.object(forKey: Self.lastCheckedKey) as? Date
    }

    static let checkEnabledKey = "app_update_check_enabled"
    static let manifestURLKey = "app_update_manifest_url"
    static let lastCheckedKey = "app_update_last_checked_at"
    static let updateVersionKey = "app_update_last_available_version"

    var isUpdateCheckEnabled: Bool {
        if let value = userDefaults.object(forKey: Self.checkEnabledKey) as? Bool {
            return value
        }
        return true
    }

    var manifestURL: String {
        userDefaults.string(forKey: Self.manifestURLKey) ?? Self.defaultManifestURL
    }

    var statusSummary: String {
        switch state {
        case .idle:
            return "Update not started"
        case .checking:
            return "Checking for updates..."
        case .disabled:
            return "Update checks disabled"
        case .upToDate:
            return "Up to date"
        case .available(let manifest):
            let buildText = manifest.build.flatMap { " (\($0))" } ?? ""
            return "Available \(manifest.version)\(buildText)"
        case .failed(let errorMessage):
            return "Check failed: \(errorMessage)"
        }
    }

    func setUpdateCheckEnabled(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: Self.checkEnabledKey)
        state = isEnabled ? .idle : .disabled
        availableUpdate = nil
    }

    func setManifestURL(_ urlString: String) {
        userDefaults.set(urlString.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.manifestURLKey)
    }

    func resetState() {
        if isUpdateCheckEnabled {
            state = .idle
        } else {
            state = .disabled
        }
        availableUpdate = nil
    }

    func currentVersion() -> String {
        currentVersionProvider()
    }

    func currentBuild() -> String {
        currentBuildProvider()
    }
}
