## Bug Fix Record
- Categoria: A
- Bug: un nuovo turno chat sulla stessa conversazione poteva partire mentre il `PipelineConversationRuntime` precedente risultava ancora `running`, impedendo la creazione del runtime del turno nuovo.
- Sintomo: il messaggio assistente nuovo riceveva testo live e tool trace, ma non una timeline pipeline reale; nei log compariva `no_pipeline_turn` per il turno corrente mentre il runtime precedente restava attivo su un altro `assistantMessageId`.
- Impatto: la chat mostrava risposte monolitiche e/o accodate ai tool, con interleaving degradato sul turno corrente.
- Gravità: alta, perché rompe il flusso core della chat agent e produce stato incoerente tra UI, trace e pipeline runtime.
- Steps to reproduce:
  1. Avviare un turno agent che usa `agentPipeline`.
  2. Inviare un nuovo turno sulla stessa conversazione prima che il runtime precedente sia stato teardown correttamente.
  3. Osservare che il nuovo assistant message non riceve un `PipelineConversationRuntime` dedicato.
- Risultato attuale: `PipelineIntegrationService.executeJob(...)` usciva subito con `return` se `isRunning(for: conversationId)` era ancora vero.
- Risultato atteso: un nuovo job sulla stessa conversazione deve sostituire il runtime precedente, non essere ignorato.
- Causa probabile: guardia silenziosa in `executeJob(...)` che non ripuliva il runtime esistente e lasciava il turno nuovo senza stato pipeline.
- Scope consentito:
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift`
  - `/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/PipelineIntegrationLifecycleTests.swift`
- Non-scope:
  - render SwiftUI della timeline
  - bridge Rust UI intent
  - store persistence
  - mapping dei raw event del ramo standard stream
- Moduli confinanti da verificare:
  - `PipelineIntegrationServiceTests`
  - `PipelineIntegrationLifecycleTests`
  - `ChatStorePipelineInterleavingPersistenceTests`
  - `ChatTimelineInterleavingTests`
- Test da aggiungere o aggiornare:
  - regressione che avvia due `executeJob(...)` consecutivi sulla stessa conversazione e verifica che lo snapshot passi al nuovo `assistantMessageId`
- Strategia di fix minimo:
  - sostituire il runtime precedente con `discardConversationRuntime(for:)` all’inizio di `executeJob(...)` quando la conversazione è ancora `running`
  - lasciare invariati gli altri contratti del service
- Verifica post-fix:
  - suite mirata lifecycle/pipeline/chat passata
  - verifica logica del nuovo snapshot `assistantMessageId` coperta da test
- Commit previsto: `fix(chat): replace stale pipeline runtime on new turns`
