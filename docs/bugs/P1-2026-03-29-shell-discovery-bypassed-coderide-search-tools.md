# P1 — I provider potevano ancora usare shell discovery al posto dei tool `coderide_*`

## Bug Fix Record
- Categoria: B
- Bug: i prompt comuni e il runtime con tool `bash` permettevano ancora ai provider di usare `grep`, `rg`, `find`, `fd`, `cat`, `ls` o `tree` nel workspace invece dei tool `coderide_*`, e la UI appiattiva le ricerche sotto etichette poco distinguibili.
- Sintomo: in chat si vedevano comandi shell tipo `grep -r` o `rg`, mentre `semantic_search` / `instant_grep` risultavano poco evidenti o assenti a livello percettivo.
- Impatto: adozione incompleta dei tool MCP workspace, performance peggiori, minore coerenza cross-provider, percezione che `Semantic Search` non venga usato.
- Gravita': P1
- Steps to reproduce:
  1. Avviare una sessione tool-enabled con tool workspace `coderide_*` disponibili.
  2. Chiedere discovery o search sul codice.
  3. Osservare che il modello puo' ancora proporre `bash` con `grep`, `rg`, `find` o letture shell, e che la UI mostra etichette generiche come `Ricerca`.
- Risultato attuale: i tool workspace sono solo preferiti dal prompt, non davvero enforced, e la UI non distingue bene `Semantic Search` da `Instant Grep`.
- Risultato atteso: tutti i provider devono usare i tool workspace strutturati per discovery/search; la shell deve restare per git/build/test/install; la UI deve mostrare `Semantic Search`, `Instant Grep` e `Codebase Search` in modo esplicito.
- Causa probabile: policy ancora troppo permissive nei prompt/provider profile, nessun guardrail runtime contro shell discovery, etichette UI troppo aggregate.
- Scope consentito:
  - template provisioning Codex
  - prompt comuni/provider
  - validazione runtime comune del tool `bash`
  - presentazione UI delle righe trace di ricerca
- Non-scope:
  - redesign completo della timeline
  - refactor dell'indice semantic/vector
  - sostituzione dell'implementazione interna di grep/semantic search
- Moduli confinanti da verificare:
  - `PromptCore`
  - `PromptToolsPolicy`
  - `ToolEnabledLLMProvider+Policy`
  - `UnifiedToolRuntime` validation
  - `ChatTurnInlineToolGroupRowPresentation`
- Test da aggiungere o aggiornare:
  - template Codex con `coderide_semantic_search` e divieto shell discovery
  - prompt strict con divieto shell discovery
  - runtime test che blocchi `bash` con `rg`
  - UI presentation tests con label dedicate
- Strategia di fix minimo:
  - rafforzare il prompt su tutti i provider
  - bloccare via runtime i comandi shell di discovery workspace
  - rendere la UI esplicita su `Semantic Search` / `Instant Grep`
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SystemPromptsTests/testTaskCompletionStrictPrefersCoderideAliasesInToolGuidance -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testBashRejectsWorkspaceDiscoveryViaRipgrep`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CLIProfileProvisionerInstructionSyncTests/testCodexInstructionsTemplateIncludesUpdatedTodoWorkflowGuardrails -only-testing:SoloCodeAppTests/ChatTurnInlineToolGroupRowPresentationTests/testSemanticSearchPresentationUsesDedicatedLabel -only-testing:SoloCodeAppTests/ChatTurnInlineToolGroupRowPresentationTests/testCodebaseSearchPresentationUsesDedicatedLabel -only-testing:SoloCodeAppTests/ChatTurnInlineToolGroupRowPresentationTests/testGrepPresentationUsesInstantGrepLabel`
- Commit previsto: `fix(search): enforce coderide workspace discovery tools across providers`
