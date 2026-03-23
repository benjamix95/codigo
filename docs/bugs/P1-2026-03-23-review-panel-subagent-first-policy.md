# P1 — 2026-03-23 — Review panel imponeva subagent come prima azione senza risposta iniziale

## Bug Fix Record
- Categoria: A — Critico
- Bug: il workflow `ToolEnabledLLMProvider` imponeva che il primo round operativo partisse subito con `subagent_*`, e le prompt policy ribadivano esplicitamente `YOUR FIRST TOOL CALL MUST ALWAYS BE 3+ subagent_explorer CALLS`.
- Sintomo:
  - il pannello review lanciava subito `subagent_explorer`, `skill`, `audit_bug_*`
  - l'utente non riceveva prima una risposta breve dell'LLM
- Impatto: UX percepita come tool-first; la chat/pannello sembrava "partire all'attacco" senza spiegare cosa stesse facendo.
- Gravita': alta
- Steps to reproduce:
  1. aprire il review panel / bug-hunt
  2. inviare una richiesta di audit o investigazione
  3. osservare che il primo output e' una raffica di tool/subagent senza frase iniziale assistant
- Risultato attuale: enforcement runtime e prompt policy spingevano il modello a delegare subito senza update user-facing.
- Risultato atteso: prima una frase breve assistant, poi eventualmente il round operativo con subagent/tool.
- Causa probabile:
  - enforcement `subagent_first_required` in `ToolEnabledLLMProvider+SendRoundProcessing.swift`
  - policy hard-coded in `ToolEnabledLLMProvider+Policy.swift`, `PromptExecutionPolicy.swift` e prompt main chat
- Scope consentito:
  - `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Send/ToolEnabledLLMProvider+Send.swift`
  - `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Send/ToolEnabledLLMProvider+SendRoundProcessing.swift`
  - `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Policies/ToolEnabledLLMProvider+Policy.swift`
  - `Engine/CoderEngine/Sources/SystemPrompts/Policies/PromptExecutionPolicy.swift`
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartO_Streaming1.swift`
- Non-scope:
  - redesign completo del pannello subagent/swarm
  - orchestrazione del provider base
- Moduli confinanti da verificare:
  - build app completa
  - test smoke del target `Solo Code`
- Test da aggiungere o aggiornare:
  - build/test smoke dei target che compilano `ToolEnabledLLMProvider` e app host
- Strategia di fix minimo:
  - rimuovere l'enforcement hard di subagent-first
  - sostituire le policy con il contratto "short user-facing update first, then operational round"
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TaskActivityVisibilityTests -only-testing:CoderEngineTests/MCPSubagentPipelineTests`
- Commit previsto: `fix(review-panel): require assistant update before subagents`
