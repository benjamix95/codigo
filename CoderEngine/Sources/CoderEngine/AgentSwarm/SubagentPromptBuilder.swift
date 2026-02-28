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
            - If everything looks good, say "No issues found."
            """
        case .testWriter:
            return """
            You are the TestWriter subagent. Write tests for the specified code.
            - Swift: use XCTest, create files in Tests/<Target>Tests/ with naming *Tests.swift
            - Node: use Jest or Vitest, file *.test.ts or __tests__/*.ts
            - Python: use pytest, file test_*.py
            Include unit tests, smoke tests, and integration tests where appropriate.
            Cover main cases and edge cases.
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
            - Report findings with severity levels and remediation suggestions
            """
        }
    }

    private static func subagentPolicy(for role: SubagentRole) -> String {
        if role == .explorer {
            return """


            **Policy:** You are a READ-ONLY subagent. Do NOT attempt to edit, create, or delete files.
            Use only search and read tools: grep, glob, read, semantic_search, codebase_search, find_symbol, find_references.
            """
        }
        return """


        **Sub-agent policy:** Do not start nested sub-agents for linear operations you can complete directly.
        Follow instructions in AGENTS.md / CLAUDE.md if present in the workspace.
        """
    }
}
