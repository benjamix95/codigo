import Foundation

enum BugHunterTriggerMode: String, Codable, Equatable, CaseIterable {
    case appAndHook = "app+hook"
    case hookOnly = "hook_only"
    case appOnly = "app_only"
}

enum BugHunterCommitMode: String, Codable, Equatable, CaseIterable {
    case postCommitAsync = "post_commit_async"
}

enum BugHunterScopeMode: String, Codable, Equatable, CaseIterable {
    case uncommittedPlusRelatedCommits = "uncommitted_plus_related_commits"
}

enum BugHunterAutofixMode: String, Codable, Equatable, CaseIterable {
    case manualPreview = "manual_preview"
    case autoHighConfidence = "auto_high_confidence"
}

enum BugHunterProfile: String, Codable, Equatable, CaseIterable {
    case quick = "bughunter_quick"
    case deep = "bughunter_deep"
    case commitReview = "bughunter_commit_review"
    case commitWindow = "bughunter_commit_window"
    case autofixRound = "bughunter_autofix_round"
    case regressionGuard = "bughunter_regression_guard"
}

struct BugHunterSettings: Codable, Equatable {
    var enabled: Bool = true
    var triggerMode: BugHunterTriggerMode = .appAndHook
    var commitMode: BugHunterCommitMode = .postCommitAsync
    var scopeMode: BugHunterScopeMode = .uncommittedPlusRelatedCommits
    var maxCommitWindow: Int = 5
    var maxRuntimeSeconds: Int = 3600
    var autofixMode: BugHunterAutofixMode = .manualPreview
    var maxAutoRounds: Int = 2
    var installGitHook: Bool = false
    var qualityGateRequired: Bool = true

    static let storageKey = "bughunter_settings_v1"
}

enum BugHunterSettingsPersistence {
    static func load() -> BugHunterSettings {
        guard let data = UserDefaults.standard.data(forKey: BugHunterSettings.storageKey) else {
            return BugHunterSettings()
        }
        return (try? JSONDecoder().decode(BugHunterSettings.self, from: data)) ?? BugHunterSettings()
    }

    static func save(_ settings: BugHunterSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: BugHunterSettings.storageKey)
    }
}

struct BugHunterCommitWindow: Equatable {
    let primaryCommit: String
    let relatedCommits: [String]
    let files: [String]
}
