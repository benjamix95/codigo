# P2 - Il flow chat session review era ancora posseduto da un file Swift dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewPanelStore+ChatSession.swift` continuava a concentrare in un file Swift legacy dedicato il flusso chat del panel review.
- Sintomo: invio messaggi, cancel stream, prompt building e persistenza di sessione chat erano ancora raccolti in un file non-UI separato.
- Impatto: il backlog del prefisso review restava piu' alto del necessario e il boundary Swift del panel chat rimaneva frammentato.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `CodeReviewPanelStore+ChatSession.swift`.
  2. Verificare che contenga sia orchestrazione chat sia helper di prompt/persistenza.
  3. Notare che il file compare ancora come legacy non-UI nel conteggio del panel review.
- Risultato attuale: il flow chat session restava in un file Swift dedicato.
- Risultato atteso: il flow chat va assorbito nei file store gia' esistenti piu' vicini al comportamento, senza nuovi file Swift non-UI.
- Causa probabile: le tranche precedenti avevano drenato launch/panel state, ma non avevano ancora riassorbito il file dedicato alla sessione chat.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - nuove API Rust
  - UI
  - modifiche engine review
- Moduli confinanti da verificare:
  - `CodeReviewPanelStore+ChatMessages.swift`
  - `CodeReviewPanelStore+SnapshotMutation.swift`
  - `CodeReviewPanelStore+CompletionFinalization.swift`
  - `CodeReviewPanelStore+TargetedFix.swift`
- Test da aggiungere o aggiornare:
  - validation review con budget gate attivo
  - targeted tests `SoloCodeAppTests` lanciati da `scripts/solocode-validate`
- Strategia di fix minimo:
  - spostare send/cancel/clear chat in `ChatMessages`
  - spostare persistenza e helper mutabili di sessione in `SnapshotMutation`
  - spostare prompt building in `CompletionFinalization`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatMessages.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+SnapshotMutation.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+CompletionFinalization.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatSession.swift,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh`
- Commit previsto: `refactor(review): distribute chat session flow into existing store files`

## Fix applicato
- `sendChatMessage`, `sendPresetMessage`, `cancelChatStream`, `clearChatHistory` spostati in `CodeReviewPanelStore+ChatMessages.swift`
- `setChatProcessing`, `persistChatState`, `ensureActiveChatThread`, `firstNonEmpty` spostati in `CodeReviewPanelStore+SnapshotMutation.swift`
- `normalizedPanelChatUserMessage`, `buildChatPrompt` e `snapshot(for:)` spostati in `CodeReviewPanelStore+CompletionFinalization.swift`
- rimosso `CodeReviewPanelStore+ChatSession.swift` dal filesystem e dal progetto Xcode

## Esito
- backlog panel review ridotto da `29` a `28`
- nessuna nuova violazione Swift non-UI
- build e test selettivi review restano verdi
