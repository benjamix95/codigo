# Bug Fix Record — 2026-03-27 — Pipeline scoped snapshot e update conversazione in-place notificato

- Categoria: B — Importante ma non bloccante
- Bug: il bridge pipeline Rust continuava a pagare costi lineari evitabili sia nella serializzazione dello store sia nell’update della conversazione target.
- Sintomo: con cronologie lunghe o molte conversazioni, gli eventi pipeline potevano introdurre lag, stutter UI e pressione inutile su CPU/memoria.
- Impatto: degrado prestazionale progressivo durante streaming e task pipeline, soprattutto su thread lunghi e workspace con molte conversazioni.
- Gravità: alta
- Steps to reproduce:
  1. Aprire una conversazione con storico lungo o molte thread già presenti nello store.
  2. Avviare uno stream pipeline con molti `textDelta` o `textReplace`.
  3. Osservare il costo crescente del bridge Rust/UI e la frequenza di invalidazioni.
- Risultato attuale:
  - al primo batch pipeline e nel path legacy il bridge costruiva ancora uno snapshot store più ampio del necessario;
  - `applyScopedForPipeline(...)` sostituiva ancora l’intero array `conversations`, pagando copia lineare anche quando cambiava una sola conversazione.
- Risultato atteso:
  - il path pipeline deve serializzare solo la conversazione attiva e gli eventuali plan board strettamente necessari;
  - l’update scoped deve mutare/aggiornare solo la conversazione target e notificare SwiftUI senza copiare tutto l’array.
- Causa probabile:
  - il caching precedente evitava rebuild completi solo dopo il primo round-trip, ma il seed iniziale e il path legacy restavano ancora dipendenti da snapshot troppo ampi;
  - la separazione tra “mutazione in-place” e “notifica throttled” del `ChatStore` non esponeva un helper dedicato per update scoped del bridge Rust.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/*`
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/*`
  - `App/SoloCodeApp/Sources/Services/ChatStore/Core/ChatStoreCore.swift`
  - test mirati in `Tests/SoloCodeAppTests`
- Non-scope:
  - refactor del reducer Rust
  - redesign dello state management SwiftUI
  - ottimizzazioni dei fan-out eventi non direttamente necessarie al fix
- Moduli confinanti da verificare:
  - bridge Rust/UI della main chat
  - pipeline runtime boundary
  - publish throttling del `ChatStore`
  - boundary tests Rust main chat
- Test da aggiungere o aggiornare:
  - test per snapshot scoped che includa solo conversazione richiesta e plan board espliciti;
  - test di regressione su `applyScopedForPipeline(...)` per publish e contenuto aggiornato.
- Strategia di fix minimo:
  - introdurre snapshot scoped riusabile per pipeline/runtime e path legacy;
  - riusare il cached snapshot scoped quando disponibile;
  - aggiungere helper `ChatStore` per upsert della conversazione target con notifica throttled senza riassegnare l’intero array;
  - splittare i file toccati sopra soglia in moduli dedicati per non lasciare nuova logica in file oversize.
- Verifica post-fix:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatStoreAdapterScopedApplyTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`
  - 18 test eseguiti, 0 failure
- Commit previsto:
  - `perf(chat): scope rust pipeline snapshots and avoid full conversation array rewrites`
