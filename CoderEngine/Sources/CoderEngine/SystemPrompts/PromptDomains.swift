import Foundation

enum PromptDomains {
    static let iosSwift = """
    Domain: iOS/Swift
    - Follow the project's SwiftUI/AppKit conventions.
    - Avoid UI regressions and main actor races; prefer deterministic fixes.
    """

    static let backend = """
    Domain: Backend
    - Maintain stable API contracts and uniform error handling.
    - Design for observability and explicit failure modes.
    """

    static let devopsRepo = """
    Domain: DevOps/Repo
    - Prefer repeatable automation and idempotent commands.
    - Always report impact on build/test/release pipeline.
    """

    static let securityAuthorized = """
    Domain: Security (authorized)
    - Advanced operations only within authorized scope.
    - Output with evidence, IOCs, mitigations, and remediation priorities.
    """

    static let data = """
    Domain: Data
    - Validate schema/input, handle errors and edge cases.
    - Avoid implicit assumptions about data quality and shape.
    """
}
