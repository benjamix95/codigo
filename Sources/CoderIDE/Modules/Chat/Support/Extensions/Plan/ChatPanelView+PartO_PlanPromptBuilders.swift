import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    // MARK: - Phase-Specific Plan Prompts

    internal func buildPhase0ScreeningPrompt(userRequest: String) -> String {
        """
        **Phase: Request Screening**

        Quickly assess whether this request needs a structured implementation plan.

        User request: \(userRequest)

        Instructions:
        1. Do NOT explore files or read code yet.
        2. Assess the request complexity in 2-3 sentences.
        3. End your response with exactly one of:
           - PLAN_NEEDED — if the request involves multiple files, architectural decisions, or non-trivial implementation
           - NO_PLAN_NEEDED — if it's a simple fix, single-file change, or straightforward task

        Be concise. This is a quick assessment, not a full analysis.
        """
    }

    internal func buildPhase1AnalysisPrompt(userRequest: String) -> String {
        """
        **Phase: Codebase Analysis (ANALYSIS ONLY)**

        You are analyzing a codebase to prepare a plan. Your ONLY task is to explore and understand the codebase.

        User request: \(userRequest)

        Instructions:
        1. Use Read, Glob, and Grep to explore files relevant to this request.
        2. Identify key files, dependencies, current architecture, and constraints.
        3. Report your findings as structured analysis text.
        4. Do NOT propose solutions, options, or clarification questions.
            5. Do NOT generate ## Todo sections or ## Plan headers.
        6. Focus on WHAT EXISTS, not what should change.
        7. Do not emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers.
        8. Include a ```mermaid diagram showing the architecture, component relationships, or data flow relevant to this request.

        Output format: A structured analysis report of your findings.
        """
    }

    internal func buildPostClarificationAnalysisPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String
    ) -> String {
        """
        **Phase: Post-clarification Analysis**

        The user answered your clarification questions. Based on the answers, perform ADDITIONAL codebase analysis.

        User request: \(userRequest)

        Previous codebase analysis:
        \(analysisContext)

        User clarification answers:
        \(clarificationAnswers)

        Instructions:
        1. Use Read, Glob, and Grep to explore specific files relevant based on the user's answers.
        2. Deep-dive into the areas indicated by the user's choices.
        3. Ask follow-up questions ONLY if there is a hard blocker. Otherwise continue without questions.
        4. If blocked, generate at most ONE additional question set using the format:

        ## Questions
        1. Question?
        A) Option A
        B) Option B
        C) Other (specify)

        5. If you have sufficient information, provide an analysis report without questions.
        6. Do NOT generate ## Plan, ## Todo or plan proposals in this phase.
        7. Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers.
        """
    }

    internal func buildPhase2QuestionPrompt(userRequest: String, analysisContext: String) -> String {
        """
        **Phase: Clarification Questions**

        Based on the codebase analysis below, determine if you need clarifications from the user.

        User request: \(userRequest)

        Codebase analysis:
        \(analysisContext)

        Instructions:
        - If you can proceed with reasonable assumptions, respond ONLY with: NO_QUESTIONS_NEEDED
        - Ask questions ONLY when blocked by missing requirements or conflicting constraints.
        - If blocked, generate 1-3 structured questions in this EXACT format:

        ## Questions
        1. Question text?
        A) First concrete option
        B) Second concrete option
        C) Third option (optional, only if useful)
        D) Other (specify)

        2. Second question?
        A) First option
        B) Second option

        STRICT rules for questions:
        - Minimum 1, maximum 3 questions
        - Each question MUST have 2-4 options labeled A) B) C) D)
        - Options must be mutually exclusive and concrete (not vague)
        - Include "D) Other (specify)" ONLY for genuinely open-ended questions
        - The header MUST be exactly "## Questions" (no localized alternatives)
        - Do NOT include ## Plan, ## Todo or plan proposals
        - Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers
        - The format must be EXACTLY as above: number + text + options A) B) C) on separate lines
        """
    }

    internal func buildPhase3GenerationPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String
    ) -> String {
        var prompt = """
        **Phase: Plan Generation**

        Generate ONE definitive implementation plan based on the analysis and context below.

        User request: \(userRequest)

        Codebase analysis:
        \(analysisContext)
        """

        if !clarificationAnswers.isEmpty {
            prompt += """

            User clarification answers:
            \(clarificationAnswers)
            """
        }

        prompt += """

        Instructions:
        - Generate ONE definitive implementation plan using this EXACT format:

        ## Plan: Title
        Description of the approach, rationale, trade-offs, and key implementation notes.

        ## Todo
        - [ ] Step 1
        - [ ] Step 2
        - [ ] Step 3

        - Include a ```mermaid diagram showing the implementation plan dependencies and flow.

        Rules:
        - The plan MUST include the exact header `## Todo`.
        - Under `## Todo`, include 3-8 checklist items using `- [ ] ...`.
        - Do NOT use alternative headers like "Tasks", "Steps", or "Checklist".
        - Steps must be concrete and directly implementable.
        - If you discover critical ambiguities that could lead to an incorrect plan, include a `## Clarifications Needed` section BEFORE the `## Todo` section listing what you need clarified. Otherwise, generate the plan directly.
        - Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers
        - During execution, prefer MCP plan tools flow:
          `plan_create` once, then `plan_step_upsert`/`plan_step_batch_update`, and finalize with `plan_set_walkthrough`.
          Keep `plan_step_update` only as legacy fallback.
        """

        return prompt
    }

    internal func buildPhase3TodoComplianceRepairPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String,
        invalidPlanOutput: String
    ) -> String {
        let clippedInvalidOutput = String(invalidPlanOutput.prefix(8_000))
        var prompt = """
        **Phase: Plan Format Repair**

        Your previous output is INVALID because the plan is missing the required `## Todo` section.
        Rewrite the plan from scratch.

        User request: \(userRequest)

        Codebase analysis:
        \(analysisContext)
        """

        if !clarificationAnswers.isEmpty {
            prompt += """

            User clarification answers:
            \(clarificationAnswers)
            """
        }

        prompt += """

        Invalid previous output (for reference):
        \(clippedInvalidOutput)

        Hard constraints (MANDATORY):
        - Output ONE plan using a `## Plan: Title` header.
        - The plan MUST contain the exact header `## Todo`
        - Under `## Todo`, include 3-8 checklist items using `- [ ]`
        - Do NOT use alternative headers like Tasks/Steps/Checklist
        - Output only the final markdown plan (no commentary)
        - Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers
        - Execution tracking should use MCP plan tools (`plan_create`, `plan_step_upsert`, `plan_step_batch_update`, `plan_set_walkthrough`).
        """

        return prompt
    }
}
