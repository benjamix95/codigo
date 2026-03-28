## Bug Fix Record
- Categoria: A
- Bug: nel ramo `agentPipeline`, il callback raw della chat continuava a spezzare il messaggio streaming e a proiettare `assistant_update` nella bolla live anche quando la pipeline non era di sua proprietà.
- Sintomo: nei log comparivano due assistant message sulla stessa conversazione:
  - uno con timeline pipeline ricca
  - uno nuovo, locale, che riceveva solo testo monolitico e marker sintetici da trace
- Impatto: risposta visibile ancora monolitica, strumenti accodati e disallineamento tra messaggio mostrato in UI e messaggio posseduto dal runtime pipeline.
- Gravità: alta, perché rompe la coerenza del flusso core chat/runtime.
- Steps to reproduce:
  1. Avviare un turno `agentPipeline` con provider Codex in linear chat.
  2. Ricevere raw event `turn_started` e `assistant_update` via callback esterno.
  3. Osservare la creazione di un secondo assistant locale e il fallback `no_pipeline_turn` sul messaggio visibile.
- Risultato attuale: `handleRawStreamEventContinuation(...)` chiamava `splitStreamingMessageForNewTurn(...)` anche quando `shouldApplyPipelineArtifacts == false`; `handleRawStreamEventContinuationSideEffects(...)` proiettava comunque `assistant_update` sul messaggio live.
- Risultato atteso: quando la pipeline artifacts ownership è esterna, il callback raw non deve mutare il main chat body né creare un nuovo assistant locale.
- Causa probabile: mancava una policy esplicita di ownership tra callback raw locali e runtime pipeline.
- Scope consentito:
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Policy/MainChatRawCallbackOwnershipPolicy.swift`
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2Continuation.swift`
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2Continuation+SideEffects.swift`
  - `/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/MainChatRawCallbackOwnershipPolicyTests.swift`
- Non-scope:
  - reducer pipeline
  - persistenza chat
  - interleaver timeline
  - lifecycle teardown del runtime pipeline
- Moduli confinanti da verificare:
  - `PipelineIntegrationLifecycleTests`
  - `MainChatRuntimeSnapshotPreferenceTests`
  - `ChatTimelineInterleavingTests`
- Test da aggiungere o aggiornare:
  - policy test che verifica il blocco di split e proiezione live quando `shouldApplyPipelineArtifacts == false`
- Strategia di fix minimo:
  - introdurre helper puro di ownership dei raw callback
  - usare la policy per impedire split e `stream_replace_text` locali quando il callback non è owner degli artifacts pipeline
- Verifica post-fix:
  - suite mirata passata
  - i file toccati restano sotto i limiti operativi
- Commit previsto: `fix(chat): honor raw callback ownership for linear split`
