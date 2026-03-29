# 2026-03-29 — Enforce `coderide_*` workspace discovery tools across providers

## Modifiche
- Rafforzato il provisioning Codex: il template ora elenca esplicitamente `coderide_semantic_search`, definisce `coderide_grep` come instant grep e vieta la shell per discovery workspace.
  - [CLIProfileProvisioner+Templates.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+Templates.swift)
- Rafforzati i prompt comuni e provider-specific: quando i tool workspace strutturati esistono, shell `grep`/`rg`/`find`/`fd`/`cat`/`ls`/`tree` non sono piu' accettati come default.
  - [PromptCore.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/SystemPrompts/Base/PromptCore.swift)
  - [PromptToolsPolicy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/SystemPrompts/Policies/PromptToolsPolicy.swift)
  - [ToolEnabledLLMProvider+Policy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Policies/ToolEnabledLLMProvider+Policy.swift)
- Aggiunto un guardrail runtime comune: il tool `bash` rifiuta i comandi shell di discovery workspace e reindirizza verso `coderide_semantic_search`, `coderide_grep`, `coderide_read`, `coderide_list_dir`, `coderide_find_files` e `coderide_glob`.
  - [UnifiedToolRuntime+ShellDiscoveryGuard.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Core/UnifiedToolRuntime+ShellDiscoveryGuard.swift)
  - [UnifiedToolRuntime+Validation.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Core/UnifiedToolRuntime+Validation.swift)
- La UI inline del trace distingue ora chiaramente `Semantic Search`, `Instant Grep`, `Codebase Search`, `Find Symbol` e `Find References`.
  - [ChatTurnInlineToolGroupRowView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnInlineToolGroupRowView.swift)
- Aggiunte regressioni su template, prompt, runtime e presentazione UI.
  - [CLIProfileProvisionerInstructionSyncTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CLIProfileProvisionerInstructionSyncTests.swift)
  - [SystemPromptsTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/SystemPromptsTests.swift)
  - [UnifiedToolRuntimeTests+RuntimeTools.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/UnifiedToolRuntime/UnifiedToolRuntimeTests+RuntimeTools.swift)
  - [ChatTurnInlineToolGroupRowPresentationTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTurnInlineToolGroupRowPresentationTests.swift)
- Registrato bug record dedicato.
  - [P1-2026-03-29-shell-discovery-bypassed-coderide-search-tools.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-29-shell-discovery-bypassed-coderide-search-tools.md)

## Risultato
- La regola ora vale su tutti gli LLM che passano per il runtime condiviso: la shell non puo' piu' essere usata come scorciatoia per discovery/search nel workspace.
- `Semantic Search` e `Instant Grep` diventano visibili in UI con etichette esplicite, quindi non risultano piu' “nascosti” sotto `Ricerca`.

## Verifica
- Test engine mirati eseguiti con successo:
  - `SystemPromptsTests/testTaskCompletionStrictPrefersCoderideAliasesInToolGuidance`
  - `UnifiedToolRuntimeTests/testBashRejectsWorkspaceDiscoveryViaRipgrep`
- Test app mirati eseguiti con successo:
  - `CLIProfileProvisionerInstructionSyncTests/testCodexInstructionsTemplateIncludesUpdatedTodoWorkflowGuardrails`
  - `ChatTurnInlineToolGroupRowPresentationTests/testSemanticSearchPresentationUsesDedicatedLabel`
  - `ChatTurnInlineToolGroupRowPresentationTests/testCodebaseSearchPresentationUsesDedicatedLabel`
  - `ChatTurnInlineToolGroupRowPresentationTests/testGrepPresentationUsesInstantGrepLabel`
