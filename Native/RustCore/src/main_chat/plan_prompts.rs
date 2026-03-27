const TODO_WRITE_PREFIX: &str = "[CODERIDE:todo_write|";
const TODO_READ: &str = "[CODERIDE:todo_read]";

pub fn build_phase0_screening_prompt(user_request: &str) -> String {
    format!(
        "**Phase: Request Screening**\n\nQuickly assess whether this request needs a structured implementation plan.\n\nUser request: {user_request}\n\nInstructions:\n1. Do NOT explore files or read code yet.\n2. Assess the request complexity in 2-3 sentences.\n3. End your response with exactly one of:\n   - PLAN_NEEDED — if the request involves multiple files, architectural decisions, or non-trivial implementation\n   - NO_PLAN_NEEDED — if it's a simple fix, single-file change, or straightforward task\n\nBe concise. This is a quick assessment, not a full analysis."
    )
}

pub fn build_phase1_analysis_prompt(user_request: &str) -> String {
    format!(
        "**Phase: Codebase Analysis (ANALYSIS ONLY)**\n\nYou are preparing a plan inside the same agent runtime used for normal execution.\n\nUser request: {user_request}\n\nInstructions:\n1. Use the same project tools, MCP tools, and subagents available in Agent mode.\n2. Planning guard is active: do NOT mutate files, run mutating commands, apply patches, or execute the implementation yet.\n3. Read/search/orchestrate/subagent investigation are allowed.\n4. Explore the files relevant to this request and identify key modules, dependencies, constraints, and risks.\n5. Report findings as structured analysis text.\n6. Do NOT propose final plan options or execution steps in this phase.\n7. Focus on WHAT EXISTS, not what should change.\n8. Do not emit {TODO_WRITE_PREFIX} or {TODO_READ} markers.\n9. Include a ```mermaid diagram when it materially helps explain architecture or data flow.\n\nOutput format: a structured analysis report."
    )
}

pub fn build_post_clarification_analysis_prompt(
    user_request: &str,
    analysis_context: &str,
    clarification_answers: &str,
) -> String {
    format!(
        "**Phase: Post-clarification Analysis**\n\nThe user answered your clarification questions. Based on the answers, perform ADDITIONAL codebase analysis.\n\nUser request: {user_request}\n\nPrevious codebase analysis:\n{analysis_context}\n\nUser clarification answers:\n{clarification_answers}\n\nInstructions:\n1. Use the same project tools, MCP tools, and subagents available in Agent mode.\n2. Planning guard is active: do NOT mutate files, run mutating commands, apply patches, or execute the implementation yet.\n3. Deep-dive into the areas indicated by the user's choices.\n4. Ask follow-up questions ONLY if there is a hard blocker. Otherwise continue without questions.\n5. If blocked, call `plan_request_user_input` with a structured `questions` JSON array (1-3 questions, 2-4 options each).\n6. Keep the actual questions visible in the chat output; do not hide them behind panel-only state.\n7. If you have sufficient information, provide an analysis report without questions.\n8. Do NOT generate ## Plan, ## Todo or plan proposals in this phase.\n9. Do NOT emit {TODO_WRITE_PREFIX} or {TODO_READ} markers."
    )
}

pub fn build_phase2_question_prompt(user_request: &str, analysis_context: &str) -> String {
    format!(
        "**Phase: Clarification Questions**\n\nBased on the codebase analysis below, determine if you need clarifications from the user.\n\nUser request: {user_request}\n\nCodebase analysis:\n{analysis_context}\n\nInstructions:\n- If you can proceed with reasonable assumptions, respond ONLY with: NO_QUESTIONS_NEEDED\n- Ask questions ONLY when blocked by missing requirements or conflicting constraints.\n- If blocked, call `plan_request_user_input` with 1-3 structured questions.\n- Keep the actual questions visible in the chat output.\n- Do NOT include ## Plan, ## Todo, or plan proposals in this phase.\n- Do NOT emit {TODO_WRITE_PREFIX} or {TODO_READ} markers."
    )
}

pub fn build_phase3_generation_prompt(
    user_request: &str,
    analysis_context: &str,
    clarification_answers: &str,
) -> String {
    let clarification_block = if clarification_answers.trim().is_empty() {
        String::new()
    } else {
        format!("\n\nUser clarification answers:\n{clarification_answers}")
    };
    format!(
        "**Phase: Plan Generation**\n\nGenerate ONE definitive implementation plan based on the analysis and context below.\n\nUser request: {user_request}\n\nCodebase analysis:\n{analysis_context}{clarification_block}\n\nInstructions:\n- Generate ONE definitive implementation plan using this EXACT format:\n\n## Plan: Title\nDescription of the approach, rationale, trade-offs, and key implementation notes.\n\n## Todo\n- [ ] Step 1\n- [ ] Step 2\n- [ ] Step 3\n\n- Include a ```mermaid diagram showing the implementation plan dependencies and flow.\n\nRules:\n- The plan MUST include the exact header `## Todo`.\n- Under `## Todo`, include 3-8 checklist items using `- [ ] ...`.\n- Do NOT use alternative headers like \"Tasks\", \"Steps\", or \"Checklist\".\n- Steps must be concrete and directly implementable.\n- Do NOT emit {TODO_WRITE_PREFIX} or {TODO_READ} markers."
    )
}

pub fn build_phase3_repair_prompt(
    user_request: &str,
    analysis_context: &str,
    clarification_answers: &str,
    invalid_plan_output: &str,
) -> String {
    let invalid = invalid_plan_output.chars().take(8_000).collect::<String>();
    let clarification_block = if clarification_answers.trim().is_empty() {
        String::new()
    } else {
        format!("\n\nUser clarification answers:\n{clarification_answers}")
    };
    format!(
        "**Phase: Plan Format Repair**\n\nYour previous output is INVALID because the plan is missing the required `## Todo` section.\nRewrite the plan from scratch.\n\nUser request: {user_request}\n\nCodebase analysis:\n{analysis_context}{clarification_block}\n\nInvalid previous output (for reference):\n{invalid}\n\nHard constraints (MANDATORY):\n- Output ONE plan using a `## Plan: Title` header.\n- The plan MUST contain the exact header `## Todo`\n- Under `## Todo`, include 3-8 checklist items using `- [ ]`\n- Do NOT use alternative headers like Tasks/Steps/Checklist\n- Output only the final markdown plan (no commentary)\n- Do NOT emit {TODO_WRITE_PREFIX} or {TODO_READ} markers."
    )
}
