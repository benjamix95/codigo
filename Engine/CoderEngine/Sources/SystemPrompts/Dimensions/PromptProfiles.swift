import Foundation

public enum PromptProfile: String, CaseIterable, Sendable {
    case cursorDefault = "cursor_default"
    case planner = "planner"
    case implementer = "implementer"
    case debugger = "debugger"
    case reviewer = "reviewer"
    case finisher = "finisher"
    case seniorEngineer = "senior_engineer"
    case staffArchitect = "staff_architect"
    case principalReviewer = "principal_reviewer"
    case incidentResponder = "incident_responder"
    case securityRedBlueAuthorized = "security_red_blue_authorized"
}

public enum PromptDomain: String, CaseIterable, Sendable {
    case general = "general"
    case iosSwift = "ios_swift"
    case backend = "backend"
    case devopsRepo = "devops_repo"
    case securityAuthorized = "security_authorized"
    case data = "data"
}

public enum PromptSafetyMode: String, CaseIterable, Sendable {
    case standard = "standard"
    case strict = "strict"
    case authorizedSecurity = "authorized_security"
}

public enum PromptVerbosity: String, CaseIterable, Sendable {
    case concise = "concise"
    case normal = "normal"
    case audit = "audit"
}

public enum ToolAggressiveness: String, CaseIterable, Sendable {
    case conservative = "conservative"
    case balanced = "balanced"
    case aggressive = "aggressive"
}

public struct PromptConfig: Sendable {
    public let profile: PromptProfile
    public let domain: PromptDomain
    public let safetyMode: PromptSafetyMode
    public let verbosity: PromptVerbosity
    public let toolAggressiveness: ToolAggressiveness
    public let requiresFinalOutcome: Bool

    public init(
        profile: PromptProfile = .cursorDefault,
        domain: PromptDomain = .general,
        safetyMode: PromptSafetyMode = .strict,
        verbosity: PromptVerbosity = .normal,
        toolAggressiveness: ToolAggressiveness = .balanced,
        requiresFinalOutcome: Bool = true
    ) {
        self.profile = profile
        self.domain = domain
        self.safetyMode = safetyMode
        self.verbosity = verbosity
        self.toolAggressiveness = toolAggressiveness
        self.requiresFinalOutcome = requiresFinalOutcome
    }
}
