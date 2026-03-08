import Foundation

enum CLIProviderKind: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex CLI"
        case .claude: return "Claude CLI"
        case .gemini: return "Gemini CLI"
        }
    }

    var providerId: String {
        switch self {
        case .codex: return "codex-cli"
        case .claude: return "claude-cli"
        case .gemini: return "gemini-cli"
        }
    }

    static func fromProviderId(_ id: String) -> CLIProviderKind? {
        Self.allCases.first(where: { $0.providerId == id })
    }
}

struct CLIAccountQuotaPolicy: Codable, Equatable {
    var dailyLimitUSD: Double?
    var weeklyLimitUSD: Double?
    var monthlyLimitUSD: Double?
    var dailyTokenLimit: Int?
    var weeklyTokenLimit: Int?
    var monthlyTokenLimit: Int?

    static let empty = CLIAccountQuotaPolicy(
        dailyLimitUSD: nil,
        weeklyLimitUSD: nil,
        monthlyLimitUSD: nil,
        dailyTokenLimit: nil,
        weeklyTokenLimit: nil,
        monthlyTokenLimit: nil
    )
}

struct CLIAccountHealth: Codable, Equatable {
    var cooldownUntil: Date?
    var lastErrorCode: String?
    var consecutiveFailures: Int
    var isExhaustedLocally: Bool

    static let healthy = CLIAccountHealth(cooldownUntil: nil, lastErrorCode: nil, consecutiveFailures: 0, isExhaustedLocally: false)
}

struct CLIAccount: Identifiable, Codable, Equatable {
    var id: UUID
    var provider: CLIProviderKind
    var label: String
    var isEnabled: Bool
    var priority: Int
    var profilePath: String
    var quota: CLIAccountQuotaPolicy
    var health: CLIAccountHealth
    var lastAuthMethod: CLIAccountAuthMethod?
    var lastAuthCheckAt: Date?
    var lastAuthError: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        provider: CLIProviderKind,
        label: String,
        isEnabled: Bool,
        priority: Int,
        profilePath: String,
        quota: CLIAccountQuotaPolicy,
        health: CLIAccountHealth,
        lastAuthMethod: CLIAccountAuthMethod? = nil,
        lastAuthCheckAt: Date? = nil,
        lastAuthError: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.provider = provider
        self.label = label
        self.isEnabled = isEnabled
        self.priority = priority
        self.profilePath = profilePath
        self.quota = quota
        self.health = health
        self.lastAuthMethod = lastAuthMethod
        self.lastAuthCheckAt = lastAuthCheckAt
        self.lastAuthError = lastAuthError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case label
        case isEnabled
        case priority
        case profilePath
        case quota
        case health
        case lastAuthMethod
        case lastAuthCheckAt
        case lastAuthError
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        provider = try c.decode(CLIProviderKind.self, forKey: .provider)
        label = try c.decode(String.self, forKey: .label)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        priority = try c.decode(Int.self, forKey: .priority)
        profilePath = try c.decode(String.self, forKey: .profilePath)
        quota = try c.decode(CLIAccountQuotaPolicy.self, forKey: .quota)
        health = try c.decode(CLIAccountHealth.self, forKey: .health)
        lastAuthMethod = try c.decodeIfPresent(CLIAccountAuthMethod.self, forKey: .lastAuthMethod)
        lastAuthCheckAt = try c.decodeIfPresent(Date.self, forKey: .lastAuthCheckAt)
        lastAuthError = try c.decodeIfPresent(String.self, forKey: .lastAuthError)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

enum CLIAvailabilityState: Equatable {
    case available
    case allExhausted(reason: String)
}
