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
            You have READ-ONLY access — you can search, read files, grep, use semantic search, \
            find symbols, and analyze code structure. You CANNOT edit or create files.

            Be thorough and systematic:
            - Use grep/glob to find relevant files and patterns
            - Read key files to understand architecture and dependencies
            - Report your findings clearly and concisely
            - Include file paths and line numbers for important findings
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
            and potential improvements.

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

            - Prioritize correctness and regression risk over style
            - Focus on nil/optional misuse, force unwraps, try!, fatalError/precondition misuse, race conditions
            - Flag suspicious diffs with missing test coverage or risky control-flow changes
            - When helpful, use the `skill` tool with debugging/testing-oriented skills before falling back to generic exploration
            - Report concrete findings with file paths, line numbers, confidence, and remediation guidance
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

            - Check for injection vulnerabilities (SQL, command, XSS)
            - Verify authentication and authorization patterns
            - Look for hardcoded secrets or credentials
            - Prefer audit_security_* tools before generic search when available
            - When helpful, use the `skill` tool with security-focused skills such as security-scan
            - Report findings with severity levels and remediation suggestions
            """
        }
    }

    private static func subagentPolicy(for role: SubagentRole) -> String {
        if role == .explorer || role == .reviewer || role == .bugHunter || role == .securityAuditor {
            let roleSpecificTools: String
            switch role {
            case .reviewer:
                roleSpecificTools = "Preferred review tools: review_findings, review_diff_summary."
            case .bugHunter:
                roleSpecificTools = "Preferred bug-hunting tools: audit_bug_diff_risks, audit_bug_test_gaps, audit_bug_hotspots, diagnostics, read_lints, and matching debugging/testing skills."
            case .securityAuditor:
                roleSpecificTools = "Preferred security tools: audit_security_secrets, audit_security_dependencies, audit_security_patterns, dependency_audit, and matching security skills."
            default:
                roleSpecificTools = ""
            }
            return """


            **Policy:** You are a READ-ONLY subagent. Do NOT attempt to edit, create, or delete files.
            Use only search and read tools: grep, glob, read, semantic_search, codebase_search, find_symbol, find_references.
            \(roleSpecificTools)
            """
        }
        return """


        **Sub-agent policy:** Do not start nested sub-agents for linear operations you can complete directly.
        Follow instructions in AGENTS.md / CLAUDE.md if present in the workspace.
        """
    }
}
