fn merge_instruction_blocks(parts: &[Option<&str>]) -> Option<String> {
    let merged = parts
        .iter()
        .filter_map(|part| part.map(str::trim))
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("\n\n");
    if merged.is_empty() {
        None
    } else {
        Some(merged)
    }
}

pub(super) fn merged_codex_base_instructions(existing: Option<&str>) -> Option<String> {
    merge_instruction_blocks(&[existing, Some(codex_system_prompt())])
}

fn codex_system_prompt() -> &'static str {
    r#"
# SoloCode Codex App Server — Mandatory MCP Workflow

You are running inside SoloCode through the Codex App Server transport.

- Prefer local `coderide_*` MCP tools for workspace read/search/edit/plan/todo/debug work whenever they are available.
- If both generic built-in tools and `coderide_*` MCP tools can do the job, choose the `coderide_*` tool first.
- Treat the `coderide` MCP server as the canonical workspace tool surface for this session.
- If the live schema exposes SoloCode native `subagent_*` tools, use those as the canonical delegation path.
- Do NOT narrate provider-native collaboration, fork, or fork_context limitations to the user.
- If no `subagent_*` tool is exposed in the live schema, continue directly with normal workspace tools instead of stalling on collaboration setup.
- Do NOT use `coderide_subagent_*` MCP tools as a proxy for real subagent execution.
- For natural-language code discovery, choose `coderide_semantic_search`.
- For exact text or regex search, choose `coderide_grep`.
- For file reads, choose `coderide_read` or `coderide_read_range`.
- For symbol/index discovery, choose `coderide_codebase_search`, `coderide_find_symbol`, `coderide_find_references`, `coderide_find_files`, `coderide_glob`, or `coderide_file_outline`.
- Use shell for git/build/test/install tasks only when the structured `coderide_*` workspace tool family does not cover the job.
- Do NOT use native search/read/edit tools as first choice when an equivalent `coderide_*` MCP tool exists.
- If the runtime shows MCP/internal tool-selection candidates, prefer the `coderide` server entries first.
- In summaries and explanations, preserve the concrete `coderide_*` tool names you used instead of rewriting them as generic aliases.
"#
}

#[cfg(test)]
mod tests {
    use super::merged_codex_base_instructions;

    #[test]
    fn merged_codex_base_instructions_appends_provider_prompt() {
        let merged = merged_codex_base_instructions(Some("Project safety rules."))
            .expect("instructions should be present");

        assert!(merged.contains("Project safety rules."));
        assert!(merged.contains("SoloCode Codex App Server"));
        assert!(merged.contains("coderide_semantic_search"));
        assert!(merged.contains("coderide_grep"));
        assert!(merged.contains("If the live schema exposes SoloCode native `subagent_*` tools"));
        assert!(merged.contains("Do NOT use `coderide_subagent_*` MCP tools"));
    }

    #[test]
    fn merged_codex_base_instructions_returns_prompt_when_existing_missing() {
        let merged = merged_codex_base_instructions(None).expect("provider prompt should exist");

        assert!(merged.contains("Mandatory MCP Workflow"));
        assert!(merged.contains("coderide_*"));
    }
}
