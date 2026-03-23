# Bug Fix Record
- Categoria: A
- Bug: il ramo `agentPipeline` della chat perdeva sia la proiezione dei subagent sia la creazione concreta dei todo.
- Sintomo: durante i task chat non comparivano card subagent visibili e i `todo_write` del pipeline non producevano item reali nel `TodoStore`.
- Impatto: osservabilità ridotta del lavoro agentico e task list operativa assente o degradata.
- Gravità: alta
- Steps to reproduce:
  1. Avviare un task chat che passa dal fallback `agentPipeline`.
  2. Lasciare che la pipeline emetta `taskStarted/taskCompleted` e/o `todo_write`.
  3. Osservare chat, swarm panel e task panel.
- Risultato attuale: i task pipeline perdevano identità swarm (`swarm_id/agent_name`) e i `todo_write` batch o inline non popolavano correttamente il `TodoStore`.
- Risultato atteso: ogni task pipeline produce card subagent reali e ogni `todo_write` valido produce todo concreti.
- Causa probabile:
  - bridge UI pipeline troppo povero di metadata subagent
  - `todo_write` batch trattati come singolo todo
  - marker inline `todo_write` del testo pipeline non convertiti in raw events
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventMapping.swift`
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`
  - `Tests/SoloCodeAppTests/ChatStreamFailureHandlingTests.swift`
- Non-scope:
  - refactor del provider
  - UI layout SwiftUI
  - politiche auth/network
- Moduli confinanti da verificare:
  - `SwarmLiveReducer`
  - `TaskActivityStore`
  - `TodoStore`
  - snapshot finale subagent
- Test da aggiungere o aggiornare:
  - parsing marker inline `todo_write`
  - metadata swarm stabili per i task pipeline
- Strategia di fix minimo:
  - propagare `swarm_id/group_id/agent_name` negli eventi task pipeline
  - registrare anche `subagent_text` per il testo dei worker
  - espandere i `todo_write` batch via `EventNormalizer.normalizeTodoWrite`
  - convertire i marker inline `todo_write` del testo pipeline in raw events
- Verifica post-fix:
  - `xcodebuild test` mirato su `ChatStreamFailureHandlingTests` e `SwarmLiveReducerTests`
- Commit previsto: `fix(chat): restore pipeline subagent visibility and todo projection`
