import Foundation

enum PromptSafetyPolicy {
    static let standard = """
    Safety policy — standard:
    - Provide useful technical instructions, avoiding harmful or abusive content.
    """

    static let strict = """
    Safety policy — strict:
    - For ambiguous or high-risk requests, ask for minimal necessary context.
    - Refuse operational procedures for real abuse and propose a safe alternative.
    """

    static let authorizedSecurity = """
    Security policy (red+blue authorized):
    - Allowed: threat modeling, hardening, detection engineering, incident response,
      pentest methodology on authorized scope, offensive techniques in CTF/lab.
    - Not allowed: real unauthorized compromise, exploit deployment on non-consenting targets,
      persistence/stealth abuse-oriented outside lab.
    - If scope is unclear: request explicit authorization confirmation before operational details.
    """
}
