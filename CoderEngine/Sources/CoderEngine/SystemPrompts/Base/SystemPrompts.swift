import Foundation

public enum SystemPrompts {
    public static let taskCompletionStrict = optimized(
        config: PromptConfig(
            profile: .cursorDefault,
            domain: .general,
            safetyMode: .strict,
            verbosity: .normal,
            toolAggressiveness: .balanced,
            requiresFinalOutcome: true
        )
    )

    public static var cursorDefault: String {
        compose([
            PromptCore.identity,
            PromptCore.completion,
            PromptExecutionPolicy.completionContract,
            PromptExecutionPolicy.doNotStopEarly,
            PromptToolsPolicy.toolUsage,
            PromptPlanningPolicy.planMarkers,
            PromptModes.finisher,
        ])
    }

    public static var planner: String {
        compose([cursorDefault, PromptModes.planner])
    }

    public static var implementer: String {
        compose([cursorDefault, PromptModes.implementer])
    }

    public static var debugger: String {
        compose([cursorDefault, PromptModes.debugger])
    }

    public static var reviewer: String {
        compose([cursorDefault, PromptModes.reviewer])
    }

    public static var finisher: String {
        compose([cursorDefault, PromptModes.finisher])
    }

    public static func optimized(config: PromptConfig) -> String {
        var sections: [String] = [PromptCore.identity]

        switch config.profile {
        case .cursorDefault: sections.append(cursorDefault)
        case .planner: sections.append(planner)
        case .implementer: sections.append(implementer)
        case .debugger: sections.append(debugger)
        case .reviewer: sections.append(reviewer)
        case .finisher: sections.append(finisher)
        case .seniorEngineer: sections.append(compose([cursorDefault, PromptPersonas.seniorEngineer]))
        case .staffArchitect: sections.append(compose([cursorDefault, PromptPersonas.staffArchitect]))
        case .principalReviewer: sections.append(compose([reviewer, PromptPersonas.principalReviewer]))
        case .incidentResponder: sections.append(compose([cursorDefault, PromptPersonas.incidentResponder]))
        case .securityRedBlueAuthorized:
            sections.append(compose([cursorDefault, PromptPersonas.securityRedBlueAuthorized]))
        }

        switch config.domain {
        case .general: break
        case .iosSwift: sections.append(PromptDomains.iosSwift)
        case .backend: sections.append(PromptDomains.backend)
        case .devopsRepo: sections.append(PromptDomains.devopsRepo)
        case .securityAuthorized: sections.append(PromptDomains.securityAuthorized)
        case .data: sections.append(PromptDomains.data)
        }

        switch config.safetyMode {
        case .standard: sections.append(PromptSafetyPolicy.standard)
        case .strict: sections.append(PromptSafetyPolicy.strict)
        case .authorizedSecurity: sections.append(PromptSafetyPolicy.authorizedSecurity)
        }

        switch config.verbosity {
        case .concise: sections.append(PromptOutputStyles.concise)
        case .normal: sections.append(PromptOutputStyles.normal)
        case .audit: sections.append(PromptOutputStyles.audit)
        }

        switch config.toolAggressiveness {
        case .conservative:
            sections.append("Tool aggressiveness: use tools only when strictly necessary.")
        case .balanced:
            break
        case .aggressive:
            sections.append("Tool aggressiveness: use tools proactively whenever they improve quality or verifiability.")
        }

        if config.requiresFinalOutcome {
            sections.append("Final outcome is mandatory: do not stop without an explicit final result.")
        }

        return compose(sections)
    }

    public static func optimized(profile: PromptProfile) -> String {
        optimized(config: PromptConfig(profile: profile))
    }

    private static func compose(_ sections: [String]) -> String {
        sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
