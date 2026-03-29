# Changelog - 2026-03-29 - Codex MCP cold start hardening

- La sezione prompt MCP del provider tool-enabled non dichiara più "nessun tool MCP disponibile" quando il registry è solo freddo: ora esplicita che il warmup non autorizza fallback su shell discovery.
- Rafforzato il guard shell workspace discovery: ora intercetta anche wrapper come `command`, `builtin`, `exec`, `noglob`, `time` e token con backslash iniziale.
- Aumentato il timeout primario di warmup MCP da `750ms` a `1200ms` per ridurre i cold start borderline del server `coderide`.
- Aggiunte regressioni dedicate:
  - fallback prompt cold registry in [`ToolEnabledLLMProviderMCPWarmupTests.swift`](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ToolEnabledLLMProviderMCPWarmupTests.swift)
  - bypass shell con `command rg` in [`UnifiedToolRuntimeTests+RuntimeTools.swift`](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/UnifiedToolRuntime/UnifiedToolRuntimeTests+RuntimeTools.swift)
