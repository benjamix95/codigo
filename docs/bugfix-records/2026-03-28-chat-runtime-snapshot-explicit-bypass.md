## Bug Fix Record
- Categoria: B
- Bug: `stream_replace_text` poteva usare uno snapshot runtime esplicito più povero del `conversationRuntime`, perdendo l'interleaving testo/tool già noto in memoria.
- Sintomo: durante lo streaming la risposta assistente restava monolitica e i tool apparivano accodati invece che intervallati ai blocchi testuali.
- Impatto: degradazione funzionale del flusso chat core; la timeline mostrava `text + tool + tool ...` invece di `text + tool + text`.
- Gravità: alta per UX e correttezza del rendering live.
- Steps to reproduce:
  1. Avviare una risposta assistente con tool multipli.
  2. Lasciare avanzare `stream_replace_text` mentre arrivano anche eventi tool.
  3. Osservare che il testo finale cresce in un unico blocco e i tool restano accodati.
- Risultato attuale: il bridge UI poteva partire da uno snapshot esplicito del `flowCoordinator` e poi risincronizzare in `conversationRuntime` uno stato meno ricco.
- Risultato atteso: quando `conversationRuntime` ha più marker o segmenti testuali, deve vincere anche se il chiamante passa uno snapshot runtime esplicito.
- Causa probabile: `currentMainChatUIBridgeContext(...)` restituiva subito `runtimeSnapshot` quando presente, saltando `preferredMainChatRuntimeSnapshot(...)`; il path `applyMainChatUIIntentBridge(...)` usa spesso proprio quello snapshot esplicito.
- Scope consentito:
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_AutoTodoRuntime.swift`
  - `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartQ_RuntimeSnapshotPreference.swift`
  - `/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/MainChatRuntimeSnapshotPreferenceTests.swift`
- Non-scope:
  - reducer pipeline
  - persistenza chat
  - render interleaver SwiftUI
  - bridge Rust dei messaggi
- Moduli confinanti da verificare:
  - `MainChatUIIntentRuntimeSync`
  - `ChatStorePipelineInterleavingPersistence`
  - `ChatPipelineTimelineState`
  - `ChatTimelineInterleaving`
- Test da aggiungere o aggiornare:
  - regressione su snapshot esplicito sostituito da `conversationRuntime` più ricco
  - regressione su creazione snapshot agent quando il base snapshot manca
- Strategia di fix minimo:
  - far passare anche il `runtimeSnapshot` esplicito attraverso la preferenza del runtime conversazionale
  - estrarre la scelta snapshot in un helper puro testabile
  - spostare gli helper di snapshot in un file dedicato per mantenere il file toccato sotto la soglia operativa
- Verifica post-fix:
  - test mirati su preferenza snapshot
  - smoke test di sync runtime e interleaving chat
- Commit previsto: `fix(chat): prefer richer conversation runtime for explicit UI snapshots`
