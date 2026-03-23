import CoderEngine
import Foundation

enum MainChatProviderBackendBridge: String, Codable {
    case codexCli = "codex_cli"
    case claudeCli = "claude_cli"
    case geminiCli = "gemini_cli"
    case kiloCli = "kilo_cli"
    case openaiApi = "openai_api"
    case anthropicApi = "anthropic_api"
    case googleApi = "google_api"
}

enum MainChatRuntimeExecutionStrategyBridge: String, Codable {
    case selectedProvider = "selected_provider"
    case multiAccountRouter = "multi_account_router"
    case singleConfiguredProvider = "single_configured_provider"
    case failClosed = "fail_closed"
}

struct MainChatProviderAttachmentBridge: Codable, Equatable {
    let kind: String
    let filePath: String
    let mimeType: String?
    let filename: String
    let sizeBytes: Int64?

    init(_ attachment: LLMAttachment) {
        self.kind = attachment.kind.rawValue
        self.filePath = attachment.url.path(percentEncoded: false)
        self.mimeType = attachment.mimeType
        self.filename = attachment.filename
        self.sizeBytes = attachment.sizeBytes
    }
}

struct MainChatCLIQuotaSnapshotBridge: Codable, Equatable {
    let dailyLimitUsd: Double?
    let weeklyLimitUsd: Double?
    let monthlyLimitUsd: Double?
    let dailyTokenLimit: Int?
    let weeklyTokenLimit: Int?
    let monthlyTokenLimit: Int?

    init(_ quota: CLIAccountQuotaPolicy) {
        self.dailyLimitUsd = quota.dailyLimitUSD
        self.weeklyLimitUsd = quota.weeklyLimitUSD
        self.monthlyLimitUsd = quota.monthlyLimitUSD
        self.dailyTokenLimit = quota.dailyTokenLimit
        self.weeklyTokenLimit = quota.weeklyTokenLimit
        self.monthlyTokenLimit = quota.monthlyTokenLimit
    }
}

struct MainChatCLIHealthSnapshotBridge: Codable, Equatable {
    let cooldownUntil: Date?
    let lastErrorCode: String?
    let consecutiveFailures: Int
    let isExhaustedLocally: Bool

    init(_ health: CLIAccountHealth) {
        self.cooldownUntil = health.cooldownUntil
        self.lastErrorCode = health.lastErrorCode
        self.consecutiveFailures = health.consecutiveFailures
        self.isExhaustedLocally = health.isExhaustedLocally
    }
}

struct MainChatCLIAccountSnapshotBridge: Codable, Equatable {
    let id: String
    let provider: String
    let label: String
    let isEnabled: Bool
    let isAuthenticated: Bool
    let priority: Int
    let profilePath: String
    let envOverrides: [String: String]
    let quota: MainChatCLIQuotaSnapshotBridge
    let health: MainChatCLIHealthSnapshotBridge
    let createdAt: Date?
    let updatedAt: Date?
}

struct MainChatRuntimeProviderRegistryEntryBridge: Codable, Equatable {
    let id: String
    let isAuthenticated: Bool
}

struct MainChatProviderSessionConfigBridge: Codable, Equatable {
    let providerId: String
    let displayName: String
    let backend: MainChatProviderBackendBridge
    let workspacePath: String
    let workspacePaths: [String]
    let prompt: String
    let systemPrompt: String?
    let contextPrompt: String?
    let model: String?
    let apiKey: String?
    let baseURL: String?
    let toolDefinitionsJson: String?
    let extraHeaders: [String: String]
    let codexPath: String?
    let codexSandbox: String?
    let codexAskForApproval: String?
    let codexModelOverride: String?
    let codexReasoningEffort: String?
    let codexModelProvider: String?
    let codexFastMode: Bool
    let codexSessionFullAccess: Bool
    let codexPreferResponsesWireAPI: Bool
    let claudePath: String?
    let claudeModel: String?
    let claudeAllowedTools: [String]
    let claudeMcpServerPath: String?
    let geminiCliPath: String?
    let geminiModelOverride: String?
    var kiloPath: String? = nil
    var kiloModel: String? = nil
    let attachments: [MainChatProviderAttachmentBridge]
    let cliAccounts: [MainChatCLIAccountSnapshotBridge]
}

struct MainChatRuntimeTransportRequestBridge: Encodable {
    let schemaVersion: Int
    let selectedProviderId: String?
    let fallbackSelectedProviderId: String?
    let coderMode: String?
    let shouldRunPlanInline: Bool
    let forcePlanInline: Bool
    let preferCodeReviewRuntimeProvider: Bool?
    let planModeBackend: String
    let codeReviewExecutionBackend: String
    let openaiApiKey: String
    let openaiModel: String
    let anthropicApiKey: String
    let anthropicModel: String
    let googleApiKey: String
    let googleModel: String
    let codexModelOverride: String
    let codexSandbox: String
    let codexSessionFullAccess: Bool
    let claudeModel: String
    let claudeAllowedTools: [String]
    let geminiModelOverride: String
    let registryProviders: [MainChatRuntimeProviderRegistryEntryBridge]
    let codexCliAccounts: [MainChatCLIAccountSnapshotBridge]
    let claudeCliAccounts: [MainChatCLIAccountSnapshotBridge]
    let geminiCliAccounts: [MainChatCLIAccountSnapshotBridge]
    let multiCliAccountEnabled: Bool
    let providerAvailabilityStatus: String?
    let providerAvailabilityReason: String?
    let baseAuthenticated: Bool
}

struct MainChatRuntimeTransportResponseBridge: Decodable {
    let schemaVersion: Int
    let error: MainChatBridgeError?
    let providerId: String?
    let backend: MainChatProviderBackendBridge?
    let model: String?
    let apiKey: String?
    let baseURL: String?
    let extraHeaders: [String: String]
    let codexSandbox: String?
    let codexSessionFullAccess: Bool
    let claudeAllowedTools: [String]
    let readOnlyPlan: Bool
    let isAuthenticated: Bool
    let nativeImageAttachment: Bool
    let nativeDocumentAttachment: Bool
    let nativeFileAttachment: Bool
    let fallbackAllowed: Bool
    let useSingleConfiguredProvider: Bool
    let executionStrategy: MainChatRuntimeExecutionStrategyBridge
    let failureReason: String?
    let userFacingHint: String?
}

struct MainChatProviderSessionStartRequestBridge: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let config: MainChatProviderSessionConfigBridge
}

struct MainChatProviderSessionRequestBridge: Encodable {
    let schemaVersion: Int
    let sessionId: String
}

struct MainChatProviderSessionPollRequestBridge: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let timeoutMs: Int
}

enum MainChatProviderEventKindBridge: String, Decodable {
    case started = "started"
    case textDelta = "textDelta"
    case textReplace = "textReplace"
    case raw = "raw"
    case completed = "completed"
    case error = "error"
}

struct MainChatProviderEventBridge: Decodable, Equatable {
    let kind: MainChatProviderEventKindBridge
    let text: String
    let rawType: String?
    let payload: [String: String]
}

struct MainChatProviderSessionSnapshotBridge: Decodable, Equatable {
    let sessionId: String
    let providerId: String
    let backend: MainChatProviderBackendBridge?
    let status: String
    let terminalError: String?
    let activeAccountId: String?
    let roundRobinIndex: Int
    let emittedEventCount: Int
    let lastFailoverReason: String?

    var isTerminal: Bool {
        switch status {
        case "completed", "failed", "cancelled":
            return true
        default:
            return false
        }
    }
}

struct MainChatProviderSessionResponseBridge: Decodable {
    let schemaVersion: Int
    let error: MainChatBridgeError?
    let snapshot: MainChatProviderSessionSnapshotBridge?
    let events: [MainChatProviderEventBridge]
}

enum MainChatProviderBridgeSupport {
    static func backend(for providerId: String) -> MainChatProviderBackendBridge? {
        switch providerId {
        case "codex-cli": return .codexCli
        case "claude-cli": return .claudeCli
        case "gemini-cli": return .geminiCli
        case "kilo-cli": return .kiloCli
        case "openai-api": return .openaiApi
        case "anthropic-api": return .anthropicApi
        case "google-api": return .googleApi
        default: return nil
        }
    }

    static func attachmentCapabilities(for providerId: String) -> ProviderAttachmentCapabilities {
        switch providerId {
        case "codex-cli", "claude-cli", "openai-api", "anthropic-api":
            return ProviderAttachmentCapabilities(nativeImage: true, nativeDocument: false, nativeFile: false)
        case "kilo-cli", "gemini-cli", "google-api":
            return ProviderAttachmentCapabilities(nativeImage: false, nativeDocument: false, nativeFile: false)
        default:
            return .none
        }
    }

    static func streamEvent(from event: MainChatProviderEventBridge) -> StreamEvent? {
        switch event.kind {
        case .started:
            return .started
        case .textDelta:
            return .textDelta(event.text)
        case .textReplace:
            return .textReplace(event.text)
        case .raw:
            guard let rawType = event.rawType else { return nil }
            return .raw(type: rawType, payload: event.payload)
        case .completed:
            return .completed
        case .error:
            return .error(event.text)
        }
    }
}
