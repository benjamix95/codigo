import Foundation

// MARK: - Panel Settings

struct ReviewPanelSettings: Codable, Equatable {
    var maxWorkers: Int = 3
    var maxRounds: Int = 3
    var analysisOnly: Bool = false
    var analysisBackend: String = "auto"
    var executionBackend: String = "auto"
    var preferredMode: String = "Standard"
    var customInstructions: String = ""
    var customCommands: [ReviewPanelCustomCommand] = []

    static let storageKey = "review_panel_settings_v1"
}

// MARK: - Custom Command

struct ReviewPanelCustomCommand: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var slash: String
    var prompt: String
    var icon: String

    init(
        id: String = UUID().uuidString,
        name: String,
        slash: String,
        prompt: String,
        icon: String = "terminal"
    ) {
        self.id = id
        self.name = name
        self.slash = slash.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.prompt = prompt
        self.icon = icon
    }

    var displayCommand: String {
        slash.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// MARK: - Persistence

enum ReviewPanelSettingsPersistence {
    static func load() -> ReviewPanelSettings {
        guard let data = UserDefaults.standard.data(
            forKey: ReviewPanelSettings.storageKey
        ) else {
            return ReviewPanelSettings()
        }
        return (try? JSONDecoder().decode(
            ReviewPanelSettings.self, from: data
        )) ?? ReviewPanelSettings()
    }

    static func save(_ settings: ReviewPanelSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        UserDefaults.standard.set(data, forKey: ReviewPanelSettings.storageKey)
    }
}
