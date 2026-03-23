## 2026-03-23 - Codex managed tool runtime enforcement

- Codex ora riceve un `CODEX_HOME` gestito di default anche fuori dal multi-account, usando un profilo `_default` provisionato dall'app con `config.toml`, `AGENTS.md`, `instructions.md` e server MCP `coderide`.
- Il main chat bypassa il transport Rust per `codex-cli` quando `unifiedToolRuntimeEnabled` è attivo, così Codex resta sul path Swift `ToolEnabledLLMProvider` che applica warmup MCP, policy tool e routing/enforcement `coderide_*`.
- Aggiunti test di regressione per:
  - seeding del profilo Codex gestito di default
  - injection del `CODEX_HOME` gestito nella factory Codex
  - bypass del transport Rust per Codex con runtime unificato attivo
