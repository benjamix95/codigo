# P1 — 2026-03-23 — Main chat deve mostrare la risposta prima delle operazioni

## Bug Fix Record
- Categoria: A — Critico
- Bug: nel path Codex main chat il transport `app-server` bufferizzava i delta assistant fino al primo evento operativo, e la timeline mostrava il blocco `reasoning` dopo il feed operativo.
- Sintomo:
  - l'utente non vedeva subito la risposta assistant dopo l'invio del messaggio
  - operazioni/tool feed arrivavano prima del testo visibile
  - il `reasoning` restava sotto il feed operativo invece che tra risposta e operazioni
- Impatto: percezione di chat "muta" all'inizio del turno e timeline poco leggibile sul piano narrativo.
- Gravita': alta
- Steps to reproduce:
  1. inviare un messaggio in main chat con provider Codex
  2. far emettere testo assistant e poi eventi tool/operativi
  3. osservare l'ordine dei contenuti in chat
- Risultato attuale: il testo assistant veniva ritardato fino al primo evento operativo; il reasoning era renderizzato dopo il feed operativo.
- Risultato atteso:
  - la risposta assistant deve apparire subito
  - dopo la risposta possono arrivare operazioni/tool
  - i blocchi `reasoning` devono stare tra risposta e operazioni
- Causa probabile:
  - `CodexAgentMessageGate` in `codex_app_server.rs` implementava una policy tool-first
  - `ChatTurnView` metteva i blocchi reasoning insieme agli artifact secondari dopo il feed operativo
- Scope consentito:
  - `Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs`
  - `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift`
  - `Tests/SoloCodeAppTests/ChatTurnTimelineOrderingTests.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - redesign completo del modello timeline
  - parser legacy CodexCLI fuori dal path main chat rust
- Moduli confinanti da verificare:
  - unit test del gate Codex app-server
  - XCTest dell'ordering timeline
- Test da aggiungere o aggiornare:
  - test Rust sul gate che streamma subito il testo
  - test app sull'ordering reasoning/detail blocks
- Strategia di fix minimo:
  - rimuovere il buffering tool-first del gate Codex app-server
  - separare in `ChatTurnView` i blocchi narrative (`reasoning`) dai detail blocks
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml codex_agent_message_gate -- --nocapture`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTurnTimelineOrderingTests`
- Commit previsto: `fix(main-chat): show response before operations`
