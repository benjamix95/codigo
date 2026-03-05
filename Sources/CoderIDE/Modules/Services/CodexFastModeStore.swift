import Foundation
import CoderEngine

enum CodexFastModeStore {
    static let defaultsKey = "codex_fast_mode"
    static let defaultValue = true

    static func currentValue(userDefaults: UserDefaults = .standard) -> Bool {
        if let stored = userDefaults.object(forKey: defaultsKey) as? Bool {
            return stored
        }
        return CodexConfigLoader.load().fastMode ?? defaultValue
    }

    @discardableResult
    static func hydrateFromConfig(userDefaults: UserDefaults = .standard) -> Bool {
        let resolved = CodexConfigLoader.load().fastMode ?? defaultValue
        userDefaults.set(resolved, forKey: defaultsKey)
        return resolved
    }

    static func persist(_ isEnabled: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(isEnabled, forKey: defaultsKey)
        var config = CodexConfigLoader.load()
        config.fastMode = isEnabled
        CodexConfigLoader.save(config)
    }
}
