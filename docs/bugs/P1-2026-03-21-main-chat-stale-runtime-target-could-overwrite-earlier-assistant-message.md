# P1 - La main chat poteva sovrascrivere un assistant storico quando il target runtime era stale

## Bug Fix Record
- Priorità: P1
- Categoria: A - Critico
- Bug: nel path main chat, `stream_replace_text` e il fallback raw `assistant_update` potevano applicare testo nuovo a un assistant message precedente quando il binding `assistant_message_id` del runtime/tool trace non combaciava più con il turno attivo.
- Sintomo:
  - durante un nuovo turno, il testo appena generato compariva dentro una risposta assistant già chiusa
  - il placeholder assistant corrente restava vuoto oppure parzialmente aggiornato
  - la timeline dava l'impressione che i messaggi nuovi sovrascrivessero quelli precedenti
- Impatto: perdita di affidabilità dello storico chat e rischio di stato UI/strore incoerente su un flusso core.
- Gravità: alta
- Steps to reproduce:
  1. Avere una conversazione con almeno un assistant storico già completato.
  2. Avviare un nuovo turno assistant con placeholder corrente in streaming.
  3. Far arrivare un `stream_replace_text` o `assistant_update` quando il binding runtime/trace punta a un `assistant_message_id` stale o mancante.
  4. Osservare che l'update cadeva sul vecchio assistant o che il bridge provava comunque a mutare un target implicito.
- Risultato attuale: i path Rust/Swift cercavano di mutare comunque la timeline tramite fallback impliciti su `last assistant` o `last streaming assistant`.
- Risultato atteso: se il target assistant del turno corrente non è risolvibile in modo esatto, il sistema non deve mutare messaggi storici; i fallback Swift devono scrivere solo sul `messageId` esplicito del turno attivo.
- Causa probabile:
  - `ui_state_sync.rs` aggiornava il `last assistant` quando `assistant_message_id` non matchava
  - `resolvePipelineBindingTarget(...)` ricadeva sullo streaming assistant anche con `activeTurn` stale
  - i fallback Swift di `stream_replace_text` e `assistant_update` aggiornavano l'ultimo assistant invece del target esplicito
- Scope consentito:
  - `Native/RustCore/src/main_chat/ui_state_sync.rs`
  - `Native/RustCore/src/main_chat/ui_tests.rs`
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Adapters/PipelineLegacyChatAdapter.swift`
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2.swift`
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartQ_Finalizers.swift`
  - `Tests/SoloCodeAppTests/ChatPanelTraceBindingTests.swift`
  - `Tests/SoloCodeAppTests/RustMainChatUIBoundaryTests.swift`
  - bug doc / changelog
- Non-scope:
  - layout SwiftUI della lista messaggi
  - refactor del runtime coordinator
  - cambi strutturali al reducer pipeline
- Moduli confinanti da verificare:
  - `currentAssistantPipelineTarget`
  - `applyMainChatUIStreamIntent`
  - `handleRawStreamEvent`
  - bridge UI Rust `applyUIIntent`
- Test da aggiungere o aggiornare:
  - regressione Rust: `stream_replace_text` con `assistant_message_id` stale non deve toccare assistant storici
  - regressione app-side: il boundary UI Rust non deve sovrascrivere il messaggio precedente
  - regressione binding: `resolvePipelineBindingTarget` non deve fare fallback quando l'`activeTurn` è stale
- Strategia di fix minimo:
  - far fallire chiuso il sync Rust quando il target assistant non esiste
  - bloccare il fallback pipeline quando l'`activeTurn` non trova più il suo messaggio
  - usare `updateAssistantMessage(messageId:...)` nei fallback Swift invece di `updateLastAssistantMessage(...)`
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml main_chat::ui_tests -- --nocapture`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPanelTraceBindingTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests`
- Commit previsto: `fix(chat): stop stale streaming targets from overwriting history`
