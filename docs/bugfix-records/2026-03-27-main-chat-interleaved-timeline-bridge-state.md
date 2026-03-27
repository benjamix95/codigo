## Bug Fix Record
- Categoria: B — importante ma non bloccante
- Bug: la chat principale non interleava correttamente risposta assistant e tool trace
- Sintomo: il testo assistant finiva in un blocco separato sotto la chat mentre i tool venivano renderizzati sopra
- Impatto: timeline fuorviante del turno, perdita del contesto operativo reale
- Gravità: alta UX/core flow
- Steps to reproduce:
  1. avviare un turno assistant con testo iniziale
  2. emettere un tool event operativo
  3. emettere altro testo assistant
  4. osservare la timeline finale
- Risultato attuale: blocco testo monolitico con fallback che lo posiziona dopo i tool
- Risultato atteso: sequenza `primaryText -> toolMarker/tool trace -> primaryText`
- Causa probabile: il runtime Swift non conservava `textSegments`, `timelineSegments` e `timelineNextSequence`, e il bridge Rust non li round-trippava
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Core`
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Adapters`
  - `App/SoloCodeApp/Sources/Runtime`
  - `Tests/SoloCodeAppTests`
- Non-scope:
  - parser provider Codex/Claude
  - renderer SwiftUI finale della chat
  - store persistence non collegata alla timeline dei turni
- Moduli confinanti da verificare:
  - reducer Swift fallback
  - bridge Swift/Rust del runtime main chat
  - restore dello stato pipeline da `ChatStore`
- Test da aggiungere o aggiornare:
  - regressione app-side su segmentazione `text/tool/text`
  - round-trip bridge JSON dei campi timeline
- Strategia di fix minimo:
  - aggiungere i campi timeline mancanti
  - propagare il round-trip nel bridge
  - ricostruire la timeline durante il restore da store
  - lasciare invariato il renderer finale
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::reducer -- --nocapture`
  - `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui_state_sync -- --nocapture`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPipelineTimelineStateTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/ChatTimelineInterleavingTests`
- Commit previsto: `fix(chat): preserve interleaved timeline state across swift rust bridge`
