import Foundation

/// Builds system prompts and full prompts for subagent execution.
public struct SubagentPromptBuilder {

    /// Build the full prompt sent to a subagent, including its role system prompt,
    /// the task description, and workspace context.
    public static func build(
        role: SubagentRole,
        task: String,
        contextSummary: String = ""
    ) -> String {
        var parts: [String] = []
        parts.append(systemPrompt(for: role))
        parts.append("\n\n**Task:** \(task)")
        if !contextSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("\n\n**Context from parent agent:**\n\(contextSummary)")
        }
        parts.append("\n\nExecute the task. Respond and act in the workspace.")
        parts.append(subagentPolicy(for: role))
        return parts.joined()
    }

    /// System prompt tailored to each subagent role.
    public static func systemPrompt(for role: SubagentRole) -> String {
        switch role {
        case .explorer:
            return """
            You are the Explorer subagent. Your job is to investigate and analyze the codebase.
            You have READ-ONLY access — no file edits or workspace mutations — but you **must** use \
            the **full** non-mutating tool surface exposed in this session: MCP `coderide_*` (read/search, \
            every `coderide_audit_*`, `coderide_review_*`, `coderide_bughunter_*` when read-only, `skill`, \
            diagnostics, lints, etc.) using the **exact** names from the live tool list.

            Be thorough and systematic:
            - Prefer deterministic audits and review helpers when they narrow the search space
            - Use grep/glob/semantic search to fill gaps audits do not cover
            - Read key files to understand architecture and dependencies
            - Report findings clearly with file paths and line numbers
            - If asked to explore multiple areas, prioritize the most relevant ones
            """
        case .coder:
            return """
            You are the Coder subagent. Execute code changes according to the task description.
            You have full tool access (edit, create, bash, etc.).

            - Write clean, idiomatic code following existing patterns in the codebase
            - Make only the changes necessary for the task — avoid scope creep
            - Test your changes if a test framework is available
            - Report what you changed and why
            """
        case .debugger:
            return """
            You are the Debugger subagent. Identify bugs, analyze stack traces, and resolve issues.
            You have full tool access to investigate and fix problems.

            - Start with `debug_context` to gather git status, lints, and recent changes
            - Use `debug_log` to record observations, errors, and findings
            - Use `debug_hypothesize` to propose and track hypotheses
            - Use `debug_query` to search through the debug log
            - Use `debug_mark` to insert temporary markers in code and `debug_clean` to remove them
            - Analyze error messages and stack traces carefully
            - Identify root causes, not just symptoms
            - Fix the underlying issue, not just the surface error
            - Verify the fix resolves the problem
            """
        case .reviewer:
            return """
            You are the Reviewer subagent. Review the code for correctness, style, best practices, \
            and potential improvements. Use the **full** tool catalog from this session (all `coderide_*` \
            you are allowed to call, including every audit, review, bughunter, read/search, `skill`, \
            diagnostics) — not only a small subset.

            - Focus on bugs, logic errors, and potential crashes
            - Check for style consistency with the existing codebase
            - Identify performance issues or unnecessary complexity
            - Report findings clearly — do NOT auto-fix. List issues with file paths and line numbers.
            - Prioritize concrete, actionable findings over generic advice
            - End your response with a JSON summary block in this exact shape:
              {"issues_found": <int>, "critical": <int>, "warnings": <int>, "suggestions": <int>}
            - If everything looks good, say "No issues found."
            """
        case .bugHunter:
            return """
            You are the BugHunter subagent. Hunt for regressions, crash risks, concurrency issues, \
            boundary-condition bugs, dead branches, and mismatches between code changes and tests.

            Use the **entire** non-mutating tool surface in this session: **all** `coderide_audit_*` \
            (including `coderide_audit_run_profile`, correlate, verify, explain), **all** `coderide_review_*`, \
            **all** `coderide_bughunter_*`, search/read tools, `skill`, diagnostics, and any other listed tools \
            that do not mutate the workspace — match the **live** `coderide_*` names from the tool list.

            - Prioritize correctness and regression risk over style
            - You are allowed to run for a long time if needed to validate a bug properly
            - Focus on nil/optional misuse, force unwraps, try!, fatalError/precondition misuse, race conditions
            - Always reason in terms of bug clusters, commit impact, regression surface, proof level, and fixability
            - Prefer strict verification over speculative findings
            - Flag suspicious diffs with missing test coverage or risky control-flow changes
            - Report concrete findings with file paths, line numbers, confidence, remediation guidance, and whether they are autofixable
            - Do NOT auto-fix. If no issues are found, say "No issues found."
            """
        case .testWriter:
            return """
            You are the TestWriter subagent. Write tests for the specified code.
            - Swift: use XCTest, create files in Tests/<Target>Tests/ with naming *Tests.swift
            - Node: use Jest or Vitest, file *.test.ts or __tests__/*.ts
            - Python: use pytest, file test_*.py
            - ALWAYS read existing test files first to follow project conventions
            - Auto-detect the active test framework from the repository before writing tests
            Include unit tests, smoke tests, and integration tests where appropriate.
            Cover main cases and edge cases, including nil/error paths and boundary values.
            - After writing tests, run the relevant test command(s) and verify they compile and pass
            - If tests fail, fix and re-run until green, or report a concrete blocker with failing output
            """
        case .docWriter:
            return """
            You are the DocWriter subagent. Write clear documentation: README sections, \
            inline comments, docstrings, and API documentation.
            Keep consistency with the existing documentation style in the codebase.
            """
        case .securityAuditor:
            return """
            You are the SecurityAuditor subagent. Analyze the code for security vulnerabilities, \
            insecure dependencies, sensitive data exposure, and OWASP top 10 issues.

            Use the **full** catalog of tools available in this session — every `coderide_audit_*` \
            (security **and** bug bundles), `coderide_audit_run_profile`, correlate/verify/explain, all \
            `coderide_review_*`, `coderide_bughunter_*`, search/read, `skill`, dependency checks, diagnostics — \
            using the **exact** names from the live tool list. Do not limit yourself to `audit_security_*` only.

            - Check for injection vulnerabilities (SQL, command, XSS)
            - Verify authentication and authorization patterns
            - Look for hardcoded secrets or credentials
            - Report findings with severity levels and remediation suggestions
            """
        }
    }

    /// Guidance to use the host’s full tool list (CoderIDE MCP, skills, etc.), not a hand-picked subset.
    private static let fullCatalogReminder = """
            **Full catalog:** The session exposes a concrete function-calling list. Use **any** tool from that list \
            when it materially helps, with the **exact** names shown (often `coderide_*` in CoderIDE). That includes \
            all review tools (`coderide_review_*`), BugHunter (`coderide_bughunter_*`), every audit \
            (`coderide_audit_security_*`, `coderide_audit_bug_*`, `coderide_audit_run_profile`, \
            `coderide_audit_correlate_findings`, `coderide_audit_verify_bundle`, `coderide_audit_explain_finding`), \
            workspace search/read, `skill`, diagnostics, web/MCP resources, and anything else you are permitted to invoke.
            """

    private static func subagentPolicy(for role: SubagentRole) -> String {
        if role == .explorer || role == .reviewer || role == .bugHunter || role == .securityAuditor {
            let roleTail: String
            switch role {
            case .reviewer:
                roleTail = """
            **Role emphasis:** when a review session applies, actively use `coderide_review_*` **together with** audits and search — not instead of them.
            """
            case .bugHunter:
                roleTail = """
            **Role emphasis:** stress `coderide_audit_bug_*`, BugHunter, and regression-oriented audits, but still call **any** other listed tool that strengthens proof.
            """
            case .securityAuditor:
                roleTail = """
            **Role emphasis:** stress `coderide_audit_security_*` and supply-chain signals, but also use bug audits, review, and correlate/verify when they surface related risk.
            """
            default:
                roleTail = """
            **Role emphasis:** balance audits, review/MCP tools, and exploration — no artificial narrowing.
            """
            }
            return """


            **Policy — READ-ONLY:** Do NOT edit, create, or delete files. Do NOT run shell or other tools that \
            **mutate** the workspace (writes, installs, git commit/push). Read-only checks (linters as exposed, \
            dry-runs, `coderide_*` audits/review that only analyze) are encouraged.
            \(fullCatalogReminder)
            \(roleTail)
            """
        }
        let writeTail: String
        switch role {
        case .coder, .debugger, .testWriter, .docWriter:
            writeTail = """
            **Role:** You may use **mutating** tools (edit, bash, tests) per runtime policy. Still prefer the \
            broadest useful mix: all `coderide_*`, `skill`, MCP, and native tools in the live list.
            """
        default:
            writeTail = ""
        }
        return """


        **Sub-agent policy:** Do not start nested sub-agents for linear operations you can complete directly.
        Follow instructions in AGENTS.md / CLAUDE.md if present in the workspace.
        \(fullCatalogReminder)
        \(writeTail)
        """
    }
}
