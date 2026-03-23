import Foundation

// MARK: - Prompt Building

extension AgentWorkerAdapter {

    static func buildPrompt(
        task: TaskNode,
        role: AgentRole,
        agentName: String,
        jobId: String
    ) -> String {
        let roleInstructions = roleSpecificInstructions(for: role)
        let taskInstr = taskInstruction(for: task)
        let fileContext = task.fileScope.isEmpty
            ? ""
            : "\n\nFile scope: \(task.fileScope.joined(separator: ", "))"

        let debugInstructions = debugWorkflowInstructions(for: task, role: role)
        let markerInstructions = markerUsageInstructions(for: role)
        let workflowInstructions = planWorkflowInstructions(for: role, task: task)

        return """
        You are agent "\(agentName)" with role \(role.displayName).
        Job: \(jobId) | Task: \(task.taskId)

        ## Task
        \(taskInstr)
        \(fileContext)

        ## Role Instructions
        \(roleInstructions)

        \(workflowInstructions)

        \(debugInstructions)

        \(markerInstructions)

        Execute the task precisely. Be concise and focused.
        When you complete this task, include a brief summary of what was done.
        If tests fail or you find critical issues, mention them explicitly.
        """
    }

    static func taskInstruction(for task: TaskNode) -> String {
        if let fullPrompt = task.metadata["pipeline_full_prompt"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fullPrompt.isEmpty {
            return fullPrompt
        }
        if let reviewDescription = task.metadata["review_description"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !reviewDescription.isEmpty {
            let severity = task.metadata["review_severity"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "warning"
            return """
            Review finding cluster: \(reviewDescription)
            Severity: \(severity)
            Fix only the issues described for the files in scope.
            """
        }
        return task.title
    }

    static func roleSpecificInstructions(
        for role: AgentRole
    ) -> String {
        switch role {
        case .planner:
            return "Analyze the request and produce a structured execution plan."
        case .explorer:
            return """
            Explore the codebase to gather context needed for the task.
            Identify relevant files, dependencies, and patterns.
            Report your findings so the next agent (Coder) can proceed.
            """
        case .coder:
            return """
            Implement the changes as described. Write clean, minimal code.
            After making changes, update the todo status to reflect progress.
            Use [CODERIDE:todo_write|...] markers to report completion.
            """
        case .debugger:
            return "Investigate and fix the issue. Explain root cause briefly."
        case .reviewer:
            return """
            Review the code changes. Report findings as structured feedback.
            Use relevant skills when available for security scanning, debugging, or testing gaps.
            If you find critical issues, include "critical" in your summary.
            If all looks good, confirm the code is ready for testing.
            """
        case .bugHunter:
            return """
            Hunt for regressions, crash risks, concurrency bugs, and missing edge-case coverage.
            Prefer relevant debugging/testing skills before generic exploration when they match the task.
            Report concrete findings with file paths and remediation guidance.
            If you find critical issues, include "critical" in your summary.
            """
        case .testWriter:
            return """
            Write tests covering the changed functionality.
            Run the tests and report results.
            If tests fail, include "tests fail" in your summary.
            """
        case .docWriter:
            return """
            Update documentation to reflect the changes made.
            Include "documentation needed" in your summary if docs are required.
            """
        case .securityAuditor:
            return """
            Audit code for security vulnerabilities. Report findings.
            Prefer relevant security skills when available, then confirm with audit tools.
            If you find critical vulnerabilities, include "security vulnerability" in your summary.
            """
        }
    }

    static func markerUsageInstructions(for role: AgentRole) -> String {
        guard role == .coder || role == .debugger else { return "" }

        return """
        ## CoderIDE Markers
        You can emit these markers in your output to interact with the IDE:
        - [CODERIDE:todo_write|title=<title>|status=<done/in_progress/pending>] — Update a todo item
        - [CODERIDE:plan_step|title=<title>|status=<done/in_progress>] — Update plan step status
        - [CODERIDE:show_task_panel] — Show the task activity panel
        """
    }

    static func planWorkflowInstructions(
        for role: AgentRole,
        task: TaskNode
    ) -> String {
        guard role == .coder || role == .explorer else { return "" }

        return """
        ## Pipeline Workflow
        This task is part of a plan build pipeline. Your work feeds into the next stage:
        Explorer -> Coder -> Reviewer -> TestWriter -> DocWriter
        Current task: "\(task.title)"
        Stay focused on this specific task only. Do not attempt to complete other tasks.
        """
    }

    static func debugWorkflowInstructions(
        for task: TaskNode,
        role: AgentRole
    ) -> String {
        guard let debugStage = task.debugStage else { return "" }

        var lines: [String] = [
            "## Debug Pipeline Stage",
            "This task belongs to the debug pipeline.",
            "Stage: \(debugStage.rawValue)",
            "Execution style: \(task.executionStyle.rawValue)",
        ]

        if let phase = task.metadata["debug_phase"], !phase.isEmpty {
            lines.append("Target phase: \(phase)")
        }
        if let errorSummary = task.metadata["error_summary"], !errorSummary.isEmpty {
            lines.append("Error summary: \(errorSummary)")
        }
        if let backendPolicy = task.metadata["backend_policy"], !backendPolicy.isEmpty {
            lines.append("Backend policy: \(backendPolicy)")
        }
        if let tool = task.metadata["mcp_tool"] ?? task.metadata["debug_tool"], !tool.isEmpty {
            lines.append("Preferred tool for this stage: \(tool)")
        }
        if let action = task.metadata["action"], !action.isEmpty {
            lines.append("Required action: \(action)")
        }
        if let label = task.metadata["label"], !label.isEmpty {
            lines.append("Required label: \(label)")
        }
        if let compareWith = task.metadata["compare_with"], !compareWith.isEmpty {
            lines.append("Compare with: \(compareWith)")
        }
        if let requestKind = task.metadata["request_kind"], !requestKind.isEmpty {
            lines.append("Request kind: \(requestKind)")
        }
        if let gateKind = task.metadata["gate_kind"], !gateKind.isEmpty {
            lines.append("Gate kind: \(gateKind)")
        }
        if let questionIndex = task.metadata["question_index"], !questionIndex.isEmpty {
            lines.append("Clarification question index: \(questionIndex)")
        }
        if let targetPath = task.metadata["target_path"], !targetPath.isEmpty {
            lines.append("Target path: \(targetPath)")
        }

        switch debugStage {
        case .activateMode:
            lines.append("Activate debug mode and establish the debug session context.")
        case .sessionStart:
            lines.append("Start the structured debug session and return the active session identifier.")
        case .sessionExport:
            lines.append("Export the full debug session report after cleanup is complete.")
        case .sessionStop:
            lines.append("Stop the debug session only after the session has been resolved.")
        case .setDescribePhase:
            lines.append("Move the debug flow into the describing phase before gathering context.")
        case .setReproducePhase:
            lines.append("Move the debug flow into the reproducing phase before asking for reproduce confirmation.")
        case .setFixPhase:
            lines.append("Move the debug flow into the fixing phase before hypotheses, snapshots, and code changes.")
        case .setVerifyPhase:
            lines.append("Move the debug flow into the verifying phase before test verification and cleanup.")
        case .gatherContext:
            lines.append("Collect the minimum context needed to understand the failure.")
        case .analyzeIssue:
            lines.append("Form hypotheses and identify the likeliest root cause.")
        case .requestClarification:
            lines.append("Ask a clarifying debug question with kind=question. Collect the minimum missing context needed to continue.")
        case .requestReproduction:
            lines.append("Ask the user only for the reproduction details needed to continue.")
        case .reproduce:
            lines.append("Reproduce the issue and capture concrete evidence.")
        case .instrument:
            lines.append("Add temporary instrumentation or markers only when they help prove a hypothesis.")
        case .snapshot:
            lines.append("Capture or compare debug snapshots exactly as required by the stage metadata.")
        case .hypothesize:
            lines.append("Propose or update structured hypotheses using debug_hypothesize and evidence from the current session.")
        case .fix:
            lines.append("Apply the smallest safe fix that addresses the validated cause.")
        case .reviewFix:
            lines.append("Review the proposed fix critically and call out any blocking findings.")
        case .verify:
            lines.append("Run verification steps or tests and state clearly whether the fix holds.")
        case .clean:
            lines.append("Remove temporary debug markers and instrumentation after verification.")
        case .timeline:
            lines.append("Generate the final chronological timeline for the resolved debug session.")
        case .resolve:
            lines.append("Resolve the debug session with a concise summary of the outcome.")
        case .awaitReproduceGate:
            lines.append("Wait for the user to confirm they have reproduced the bug. Use debug_request_user kind=reproduce to prompt. The pipeline pauses until confirmation.")
        case .awaitFixGate:
            lines.append("Wait for the user to verify the fix works. Use debug_request_user kind=fix_confirmation to prompt. The pipeline pauses until the user clicks Mark Fixed.")
        case .nativeStart, .nativeRefresh, .nativeSyncBreakpoints, .nativeSyncWatches,
             .nativeStepIn, .nativeStepOver, .nativeStepOut, .nativeStop:
            lines.append("Coordinate the native debugging stage and emit state updates for the IDE.")
        }

        if role == .reviewer {
            lines.append("If you find blocking issues, say so explicitly in the summary.")
        }
        if role == .testWriter {
            lines.append("If verification fails, include that tests fail or reproduction still occurs.")
        }

        return lines.joined(separator: "\n")
    }
}
