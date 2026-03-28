# P2 - Il sync pipeline poteva perdere metadati assistant locali dopo il commit Rust

## Bug Fix Record
- Priorita': P2
- Categoria: B - Importante ma non bloccante
- Bug: il path `sync_assistant_pipeline_state` poteva lasciare in RAM un messaggio assistant aggiornato da Rust ma privo dei metadati locali non ricostruiti dal payload pipeline, in particolare `subagentCards` e `reasoningText`, e in generale i campi locali reiniettati lato Swift.
- Sintomo:
  - card subagent e reasoning locale potevano sparire dopo un commit pipeline riuscito
  - i blocchi della timeline restavano corretti ma il messaggio perdeva contesto UI locale
  - il problema emergeva soprattutto quando Rust applicava gia' testo e blocchi senza richiedere il replace completo del messaggio
- Impatto: perdita di stato visivo e metadati utili sul messaggio assistant appena sincronizzato.
- Gravita': media
- Steps to reproduce:
  1. Avere un assistant message presente in `conversations`.
  2. Aggiungere metadati solo locali al messaggio in RAM, per esempio `subagentCards` o `reasoningText`.
  3. Applicare `updateAssistantMessagePipelineState(...)` con bridge Rust attivo.
  4. Osservare che il messaggio aggiornato poteva conservare testo/blocchi pipeline ma perdere i metadati locali.
- Risultato attuale: il restore dei metadati locali dipendeva dal fatto che i blocchi Swift sostituissero l'intero messaggio; quando quel replace non avveniva, i campi locali restavano persi.
- Risultato atteso: dopo il commit pipeline, il messaggio finale deve preservare i metadati locali non descritti dal payload pipeline, indipendentemente dal fatto che il replace completo del messaggio avvenga o no.
- Causa probabile:
  - il merge locale avveniva solo sul `pipelineMessage` da sostituire
  - il path `no replace` lasciava in memoria la versione post-Rust senza reiniettare i campi locali
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+PipelineStateLocalSync.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridgeMessages.swift`
  - `Tests/SoloCodeAppTests/ChatStoreStreamingTargetTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - logging NDJSON
  - refactor del reducer Rust store
  - redesign delle timeline blocks
- Moduli confinanti da verificare:
  - propagazione `toolMarker` nel path pipeline locale
  - `updateAssistantMessagePipelineState`
  - bridge Swift/Rust del main chat store
- Test da aggiungere o aggiornare:
  - regressione app-side: i metadati assistant locali devono restare presenti dopo `sync_assistant_pipeline_state`
  - conferma del test esistente sui `toolMarker` nel commit pipeline
- Strategia di fix minimo:
  - catturare lo snapshot locale pre-commit
  - riapplicare i metadati locali sia nel path di replace completo sia nel path che mantiene il messaggio post-Rust
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests/testPipelineCommitPreservesLocalAssistantMetadataWhenRustApplySucceeds -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests/testPipelineCommitPropagatesToolMarkersWhenRustApplySucceeds`
- Commit previsto: `fix(chat): preserve local assistant metadata across pipeline sync`
