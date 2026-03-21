# P1 - Main chat: il send si interrompeva subito quando il runtime Rust mancava

## Bug Fix Record
- Categoria: A
- Bug: in `coderMode = .agent`, quando il runtime Rust risultava non disponibile (`library_missing`) il send della main chat partiva ma si fermava subito senza completare il turno.
- Sintomo: log con `executeSendMessageTurn`, `STANDARD mode path taken`, `Rust bridge unavailable — using Swift pipeline fallback for raw events`, poi chiusura immediata del flusso.
- Impatto: la chat agente non era più utilizzabile in build locali dove la dylib Rust non veniva caricata, nonostante il codice avesse già introdotto il fallback al provider Swift selezionato.
- Gravità: P1
- Steps to reproduce:
  1. Avviare l'app con `ReviewCoreBridge.isEnabled == false` e `failureReason = library_missing`.
  2. Selezionare un provider CLI standard in modalità `Agent`.
  3. Inviare un messaggio in chat.
  4. Osservare che il turno si interrompe subito.
- Risultato attuale: il fallback selezionava un provider Swift, ma `executeSendMessageTurn` lo instradava comunque nel path standard che dipende dal coordinator Rust-only.
- Risultato atteso: in modalità `Agent`, se il provider runtime non usa il trasporto Rust, il turno deve tornare al pipeline path Swift già esistente invece di entrare nel coordinator Rust-only.
- Causa probabile: regressione introdotta quando è stato rimosso il branch `.agent` dedicato in `ChatPanelView+PartL_SendMessageExecution.swift`, senza riallineare il nuovo fallback di `resolveMainChatTransportProvider`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessageExecution.swift`
  - `Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - bootstrap/linking della dylib Rust
  - refactor del `ConversationFlowCoordinator`
  - plan runtime Rust
- Moduli confinanti da verificare:
  - `resolveMainChatTransportProvider`
  - `PipelineJobFactory`
  - `AgentWorkerAdapter`
  - `PipelineIntegrationService`
- Test da aggiungere o aggiornare:
  - regression test sul routing del send in modalità agent quando il provider non usa il trasporto Rust
- Strategia di fix minimo:
  - reintrodurre il branch agent pipeline solo per il caso `coderMode == .agent && !usesRustTransport`
  - lasciare invariato il path standard per il trasporto Rust
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests`
- Commit previsto: `fix(chat): restore agent fallback when rust main-chat runtime is unavailable`
