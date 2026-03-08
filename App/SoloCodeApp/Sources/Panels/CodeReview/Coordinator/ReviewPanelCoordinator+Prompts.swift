import Foundation

// MARK: - Prompt Builders for Pipeline Modes

extension ReviewPanelCoordinator {
    static func combinedPrompt(
        scope: ReviewScopeTarget,
        currentBranch: String,
        selectedModes: Set<CodeReviewPanelMode>,
        customInstructions: String = ""
    ) -> String {
        let normalizedModes = selectedModes.isEmpty ? Set([.standard]) : selectedModes
        let scopeHeader: String = {
            switch scope {
            case .branch(let name):
                return branchReviewPrompt(branch: name, currentBranch: currentBranch)
            case .commits(let commits) where !commits.isEmpty:
                return commitRangePrompt(commits: commits)
            default:
                return """
                \(scope.scopeTag)
                Run a code review over the selected scope.
                """
            }
        }()

        var sections: [String] = [scopeHeader]
        if normalizedModes.contains(.standard) {
            sections.append(standardFocusSection)
        }
        if normalizedModes.contains(.securityAudit) {
            sections.append(securityFocusSection)
        }
        if normalizedModes.contains(.bugFinder) {
            sections.append(bugFocusSection)
        }
        if !customInstructions.isEmpty {
            sections.append("Additional instructions:\n\(customInstructions)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static let standardFocusSection = """
    Standard focus:
    - P0 (Critical): Security vulnerabilities, data loss risks, crash bugs
    - P1 (High): Logic errors, performance regressions, API misuse
    - P2 (Medium): Code quality, maintainability, potential bugs
    - P3 (Low): Style, documentation, minor improvements

    For each finding, provide severity, file, line range, description, and a suggested fix.
    """

    private static let securityFocusSection = """
    Security focus:
    1. Injection vulnerabilities: SQL injection, XSS, command injection, path traversal
    2. Authentication and authorization: bypasses, missing checks, privilege escalation
    3. Secrets and credentials: hardcoded keys, tokens, passwords
    4. Unsafe deserialization and validation issues
    5. File and network handling: unsafe file ops, SSRF, unvalidated URLs
    6. Data exposure in logs and error surfaces
    """

    private static let bugFocusSection = """
    Bug focus:
    1. Nil or null dereference and force unwraps
    2. Race conditions and invalid state transitions
    3. Logic errors, off-by-one, wrong comparisons
    4. Memory issues and unbounded growth
    5. Error handling gaps and swallowed failures
    6. Edge cases and API misuse
    """

    // MARK: - Standard

    static func standardPrompt(
        scope: ReviewScopeTarget,
        customInstructions: String = ""
    ) -> String {
        let base = """
        \(scope.scopeTag)
        Run a comprehensive code review covering:
        - P0 (Critical): Security vulnerabilities, data loss risks, crash bugs
        - P1 (High): Logic errors, performance regressions, API misuse
        - P2 (Medium): Code quality, maintainability, potential bugs
        - P3 (Low): Style, documentation, minor improvements

        For each finding, provide: severity, file, line range, description, and a suggested fix.
        """
        if customInstructions.isEmpty {
            return base
        }
        return base + "\n\nAdditional instructions:\n\(customInstructions)"
    }

    // MARK: - Security Audit

    static func securityAuditPrompt(scope: ReviewScopeTarget) -> String {
        """
        \(scope.scopeTag) [MODE:security-audit]
        Run a thorough security-focused code review. Priority areas:

        1. **Injection vulnerabilities**: SQL injection, XSS, command injection, path traversal
        2. **Authentication/Authorization**: Bypasses, missing checks, privilege escalation
        3. **Secrets & credentials**: Hardcoded keys, tokens, passwords in source code
        4. **Unsafe deserialization**: Unvalidated input, unsafe casting, type confusion
        5. **File & network handling**: Unsafe file operations, SSRF, unvalidated URLs
        6. **Dependency risks**: Known CVEs in package manifests, outdated libraries
        7. **Cryptographic issues**: Weak algorithms, improper random generation, key management
        8. **Data exposure**: Logging sensitive data, excessive error details, PII leaks

        Report each finding with:
        - Severity (Critical/High/Medium/Low)
        - Affected file and line range
        - Attack vector description
        - CVSS-like impact assessment
        - Recommended mitigation with code example
        """
    }

    // MARK: - Bug Finder

    static func bugFinderPrompt(scope: ReviewScopeTarget) -> String {
        """
        \(scope.scopeTag) [MODE:bug-finder]
        Run a bug-focused code review. Look specifically for:

        1. **Null/nil dereference**: Force unwraps, unguarded optionals, missing nil checks
        2. **Race conditions**: Shared mutable state, actor isolation violations, data races
        3. **Logic errors**: Off-by-one, incorrect comparisons, wrong operator precedence
        4. **Memory issues**: Retain cycles, leaked resources, unbounded growth
        5. **Error handling**: Swallowed errors, incorrect catch blocks, missing error propagation
        6. **API misuse**: Wrong parameter types/order, deprecated APIs, contract violations
        7. **Edge cases**: Empty collections, boundary values, integer overflow
        8. **State management**: Invalid state transitions, stale data, inconsistent updates

        For each bug found, provide:
        - Severity and category
        - Exact reproduction scenario
        - Root cause analysis
        - Fix with code diff
        """
    }

    // MARK: - Branch Review

    static func branchReviewPrompt(
        branch: String,
        currentBranch: String
    ) -> String {
        """
        [AGAINST:\(currentBranch)..\(branch)]
        Review all changes on branch '\(branch)' since it diverged from '\(currentBranch)'.

        Analyze the entire branch for:
        - Cumulative impact of all commits
        - Patterns of issues across multiple files
        - Architectural concerns from the combined changeset
        - Regression risks when merging
        - Incomplete features or TODO items left behind
        - Test coverage gaps for new code

        Group findings by commit when possible, and highlight cross-cutting concerns.
        """
    }

    // MARK: - Commit Range

    static func commitRangePrompt(commits: [String]) -> String {
        let shas = commits.joined(separator: ", ")
        let scope: String
        if commits.count == 1 {
            scope = "[AGAINST:\(commits[0])^..\(commits[0])]"
        } else if let first = commits.last, let last = commits.first {
            scope = "[AGAINST:\(first)^..\(last)]"
        } else {
            scope = "[REVIEW_SCOPE:uncommitted]"
        }

        return """
        \(scope)
        Review the following commits: \(shas)

        For each commit, analyze:
        - Code quality and correctness
        - Security implications
        - Performance impact
        - Test coverage

        Summarize findings grouped by commit SHA with cross-references.
        """
    }

    // MARK: - Chat Context Prompt

    static func chatContextPrompt(
        userMessage: String,
        sessionSummary: String,
        findingsCount: Int,
        openCount: Int,
        activeSessionId: String?,
        conversationId: UUID?
    ) -> String {
        let sessionLine = activeSessionId.map { "- Active review session: \($0)" }
            ?? "- Active review session: unavailable"
        let conversationLine = conversationId.map { "- Conversation scope: \($0.uuidString)" }
            ?? "- Conversation scope: none"
        return """
        You are the dedicated chat for an active code review session.
        Your primary focus is bug hunting, regression detection, security review, and test gaps.
        You have access to the full tool-enabled review environment exposed by the runtime. When a tool can materially improve accuracy, use it instead of guessing.
        Prefer bug-hunter and security-auditor behaviour: verify before asserting, prioritize concrete risks, and surface only actionable findings.

        Current review state:
        \(sessionLine)
        \(conversationLine)
        \(sessionSummary)
        - Total findings: \(findingsCount)
        - Open findings: \(openCount)

        Response contract:
        - Use well-structured markdown, not dense plain text.
        - Start with a short title or verdict only when useful.
        - Prefer these sections when applicable: `## Findings`, `## Security`, `## Reproduction`, `## Fix`, `## Risks`, `## Next checks`.
        - Use bullets for distinct issues and short paragraphs for explanations.
        - Reference findings by severity, file, and line whenever possible.
        - When no bug or security issue is confirmed, say that explicitly and note residual risks or missing verification.
        - Do not pad the answer with generic praise or filler.

        If you identify NEW actionable findings that should appear in the Findings tab, append at the very end a fenced block exactly like this:

        ```review_findings
        {
          "findings": [
            {
              "severity": "warning",
              "category": "correctness",
              "file": "Sources/App/Main.swift",
              "line": 42,
              "message": "Short actionable finding",
              "suggested_fix": "Concrete fix guidance",
              "confidence": 0.82
            }
          ]
        }
        ```

        Rules:
        - Reuse the current active review session for review tools and findings updates.
        - Do not call `review_start` unless the user explicitly asks to start a new review session.
        - When a review tool accepts them, always pass `session_id` and `conversation_id` for the active session above.
        - Emit the block only when you are introducing or updating actionable findings.
        - If there are no actionable findings, do not emit the block.
        - Use categories: correctness, regression, concurrency, security, tests, maintainability, performance, other.
        - Severity: critical, warning, suggestion, info.
        - Keep the fenced `review_findings` block as the final trailing block only.
        - Do not wrap the whole answer in a code fence.

        User: \(userMessage)
        """
    }
}
