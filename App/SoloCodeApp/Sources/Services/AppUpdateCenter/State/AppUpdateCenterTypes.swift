import Foundation

@MainActor
extension AppUpdateCenter {
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
                return "Release note: \(URL(string: changelogURL)?.lastPathComponent ?? changelogURL)"
            }
            return "No release notes available"
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
}
