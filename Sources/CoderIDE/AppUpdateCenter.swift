import Foundation
import OSLog
import SwiftUI

@MainActor
final class AppUpdateCenter: ObservableObject {
    static let defaultManifestURL = "https://raw.githubusercontent.com/benjamix95/codigo/main/docs/update/manifest.json"
    static let checkInterval: TimeInterval = 60 * 60 * 24

    enum UpdateState: Equatable {
        case idle
        case checking
        case disabled
        case upToDate
        case available(AppUpdateManifest)
        case failed(String)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }
    }

    struct AppUpdateManifest: Codable, Equatable, Identifiable {
        let schema: Int?
        let version: String
        let build: String?
        let minimumSystemVersion: String?
        let releaseDate: String?
        let required: Bool?
        let downloadURL: String?
        let releaseNotes: String?
        let releaseNotesURL: String?
        let changelogURL: String?
        let notes: String?
        let changelog: String?

        var id: String {
            "\(version)-\(build ?? "0")"
        }

        var displayBuild: String {
            build ?? "0"
        }

        var shortNotes: String {
            if let releaseNotes, !releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return releaseNotes
            }
            if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return notes
            }
            if let changelog, !changelog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return changelog
            }
            if let changelogURL, !changelogURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Nota tecnica: \(URL(string: changelogURL)?.lastPathComponent ?? changelogURL)"
            }
            return "Nessuna nota disponibile"
        }

        enum CodingKeys: String, CodingKey {
            case schema
            case version
            case build
            case minimumSystemVersion = "minimum_system_version"
            case releaseDate = "release_date"
            case required
            case downloadURL = "download_url"
            case releaseNotes = "release_notes"
            case releaseNotesURL = "release_notes_url"
            case changelogURL = "changelog_url"
            case changelog = "changelog"
            case notes = "notes"
        }
    }

    struct AppVersion: Comparable, Equatable {
        let raw: String
        let components: [Int]

        init?(_ value: String) {
            raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let semantic = raw
                .split(separator: "+", maxSplits: 1)
                .first
                .map(String.init) ?? raw
            let core = semantic
                .split(separator: "-", maxSplits: 1)
                .first
                .map(String.init) ?? semantic
        let parsed = core
            .split(separator: ".")
            .compactMap { token -> Int? in
                let onlyNumbers = String(token.filter(\.isNumber))
                guard !onlyNumbers.isEmpty else { return nil }
                return Int(onlyNumbers)
            }
            guard !parsed.isEmpty else { return nil }
            components = parsed
        }

        static func < (lhs: AppUpdateCenter.AppVersion, rhs: AppUpdateCenter.AppVersion) -> Bool {
            let maxCount = max(lhs.components.count, rhs.components.count)
            for index in 0..<maxCount {
                let left = lhs.components.indices.contains(index) ? lhs.components[index] : 0
                let right = rhs.components.indices.contains(index) ? rhs.components[index] : 0
                if left != right { return left < right }
            }
            return false
        }
    }

    private static let checkEnabledKey = "app_update_check_enabled"
    private static let manifestURLKey = "app_update_manifest_url"
    private static let lastCheckedKey = "app_update_last_checked_at"
    private static let updateVersionKey = "app_update_last_available_version"

    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var availableUpdate: AppUpdateManifest?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.codigo.app", category: "update")
    private let userDefaults: UserDefaults
    private let urlSession: URLSession

    init(userDefaults: UserDefaults = .standard, urlSession: URLSession = .shared) {
        self.userDefaults = userDefaults
        self.urlSession = urlSession
        self.lastCheckedAt = userDefaults.object(forKey: Self.lastCheckedKey) as? Date
    }

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
            return "Aggiornamento non avviato"
        case .checking:
            return "Controllo aggiornamenti in corso..."
        case .disabled:
            return "Controllo aggiornamenti disabilitato"
        case .upToDate:
            return "Aggiornamento non necessario"
        case .available(let manifest):
            let buildText = manifest.build.flatMap { " (\($0))" } ?? ""
            return "Disponibile \(manifest.version)\(buildText)"
        case .failed(let errorMessage):
            return "Errore controllo: \(errorMessage)"
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

    func checkForUpdates(force: Bool = false) async {
        guard isUpdateCheckEnabled else {
            state = .disabled
            availableUpdate = nil
            return
        }

        if !force && !shouldCheckNow() {
            if state == .idle || state == .disabled {
                state = .upToDate
            }
            return
        }

        guard let manifestURL = URL(string: manifestURL), !manifestURL.absoluteString.isEmpty else {
            lastError = "Manifest URL non valido."
            state = .failed(lastError ?? "")
            availableUpdate = nil
            return
        }

        state = .checking
        lastError = nil

        do {
            let request = URLRequest(url: manifestURL, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 8)
            let (data, response) = try await urlSession.data(for: request)
            updateLastChecked()

            try validate(response: response)

            let decoder = JSONDecoder()
            let manifest = try decoder.decode(AppUpdateManifest.self, from: data)
            let localVersion = currentVersion()
            let localBuild = currentBuild()

            guard manifest.version.isEmpty == false else {
                throw NSError(
                    domain: "AppUpdateCenter",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "Manifest mancante della versione."]
                )
            }

            guard AppUpdateCenter.isCompatible(with: manifest.minimumSystemVersion) else {
                throw NSError(
                    domain: "AppUpdateCenter",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "Aggiornamento non compatibile con questa versione macOS."]
                )
            }

            if AppUpdateCenter.shouldUpdate(localVersion: localVersion, localBuild: localBuild, manifest: manifest) {
                availableUpdate = manifest
                lastError = nil
                state = .available(manifest)
            } else {
                availableUpdate = nil
                state = .upToDate
            }

            userDefaults.set(manifest.version, forKey: Self.updateVersionKey)
            userDefaults.set(manifest.shortNotes, forKey: "\(Self.updateVersionKey)_last_notes")
        } catch {
            let message = error.localizedDescription
            logger.error("Update check failed: \(message, privacy: .public)")
            lastError = message
            state = .failed(message)
            availableUpdate = nil
        }
    }

    nonisolated static func shouldUpdate(localVersion: String, localBuild: String, manifest: AppUpdateManifest) -> Bool {
        guard
            let localParsed = AppVersion(localVersion),
            let remoteParsed = AppVersion(manifest.version)
        else {
            return false
        }

        if remoteParsed > localParsed { return true }
        guard remoteParsed == localParsed else { return false }
        guard
            let localBuildInt = Int(localBuild),
            let remoteBuildInt = Int(manifest.displayBuild)
        else {
            return false
        }
        return remoteBuildInt > localBuildInt
    }

    nonisolated static func isCompatible(with minimumSystemVersion: String?) -> Bool {
        guard
            let minimumSystemVersion,
            let minimumParsed = AppVersion(minimumSystemVersion)
        else {
            return true
        }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let current = AppVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)") ?? AppVersion("14.0")!
        return current >= minimumParsed
    }

    private func shouldCheckNow() -> Bool {
        let latestDate = lastCheckedAt ?? userDefaults.object(forKey: Self.lastCheckedKey) as? Date
        if latestDate == nil { return true }
        let elapsed = Date().timeIntervalSince(latestDate!)
        return elapsed >= Self.checkInterval
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw NSError(
                domain: "AppUpdateCenter",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Risposta server non valida."]
            )
        }
        guard (200...299).contains(response.statusCode) else {
            throw NSError(
                domain: "AppUpdateCenter",
                code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Errore server: \(response.statusCode)."]
            )
        }
    }

    private func updateLastChecked() {
        let now = Date()
        lastCheckedAt = now
        userDefaults.set(now, forKey: Self.lastCheckedKey)
    }

    func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func currentBuild() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
