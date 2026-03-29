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

- Prefer local `coderide_*` MCP tools for workspace read/search/edit/plan/todo/debug/subagent work whenever they are available.
- If both generic built-in tools and `coderide_*` MCP tools can do the job, choose the `coderide_*` tool first.
- Treat the `coderide` MCP server as the canonical workspace tool surface for this session.
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
    }

    #[test]
    fn merged_codex_base_instructions_returns_prompt_when_existing_missing() {
        let merged = merged_codex_base_instructions(None).expect("provider prompt should exist");

        assert!(merged.contains("Mandatory MCP Workflow"));
        assert!(merged.contains("coderide_*"));
    }
}
