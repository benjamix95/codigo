#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

print_section() {
  local title="$1"
  echo
  echo "== $title =="
}

check_cli() {
  local name="$1"
  local command_name="$2"
  if command -v "$command_name" >/dev/null 2>&1; then
    echo "[ok] $name CLI detected ($command_name)"
  else
    echo "[skip] $name CLI not found ($command_name)"
  fi
}

check_env_key() {
  local label="$1"
  local var_name="$2"
  if [[ -n "${!var_name:-}" ]]; then
    echo "[ok] $label key available (\$$var_name)"
  else
    echo "[skip] $label key missing (\$$var_name)"
  fi
}

run_cmd() {
  local cmd="$1"
  echo "[run] $cmd"
  eval "$cmd"
}

print_section "Preflight"
check_cli "Codex" "codex"
check_cli "Claude" "claude"
check_cli "Gemini" "gemini"
check_cli "ripgrep" "rg"

check_env_key "OpenAI" "OPENAI_API_KEY"
check_env_key "Anthropic" "ANTHROPIC_API_KEY"
check_env_key "Google" "GOOGLE_API_KEY"
check_env_key "OpenRouter" "OPENROUTER_API_KEY"
check_env_key "MiniMax" "MINIMAX_API_KEY"
check_env_key "Grok/xAI" "GROK_API_KEY"

print_section "Automated smoke checks"
run_cmd "cd \"$ROOT_DIR\" && bash scripts/check_english_only.sh"
run_cmd "cd \"$ROOT_DIR\" && swift test --filter ProviderFactoryRuntimeParityTests"
run_cmd "cd \"$ROOT_DIR/CoderEngine\" && swift test --filter UnifiedToolRuntimeTests/testSemanticSearchLimitAliasTakesPriority"
run_cmd "cd \"$ROOT_DIR/CoderEngine\" && swift test --filter UnifiedToolRuntimeTests/testSemanticSearchFallbackSupportsMultipleTargetDirectories"
run_cmd "cd \"$ROOT_DIR/CoderEngine\" && swift test --filter UnifiedToolRuntimeTests/testGrepMultiScopeProducesPreviewAndCountPayload"
run_cmd "cd \"$ROOT_DIR/CoderEngine\" && swift test --filter ToolEnabledLLMProviderInstantGrepTests"
run_cmd "cd \"$ROOT_DIR\" && swift test --filter EventNormalizerLiveStateTests/testReadBatchCompletedSemanticSearchMapsToSemanticType"

print_section "Manual QA matrix"
cat <<'EOF'
Run this checklist in the app for each provider (OpenAI, Anthropic, Google, OpenRouter, MiniMax, Grok, Codex CLI, Claude CLI, Gemini CLI):

1. Ask a natural-language code query and confirm:
   - semantic trace appears as semantic_search
   - no "index not available" when a workspace is active

2. Trigger instant grep and confirm:
   - immediate results are shown
   - matchesCount, previewLines, duration_ms, pathScope are populated in activity payload

3. Switch active workspace and confirm:
   - follow-up search results come from the new workspace paths

4. Delete a file and confirm:
   - file disappears immediately from semantic/codebase search
   - no ghost results after a follow-up query
EOF

print_section "Completed"
echo "Search flow QA script finished."
