# P2 - I bridge review gia' spostati su Rust restavano frammentati in quattro file Swift legacy

## Bug Fix Record
- Categoria: B
- Bug: una parte del panel review era gia' solo wrapper verso boundary Rust, ma rimaneva spezzata in quattro file Swift non-UI separati.
- Sintomo: `CodeReviewPanelStore+RustChatFindings.swift`, `CodeReviewPanelStore+RustHistoricalFindings.swift`, `CodeReviewPanelStore+RustLaunchPlanning.swift` e `CodeReviewPanelStore+RustCompletionFinalization.swift` aggiungevano debito di file legacy pur non contenendo piu' logica business Swift significativa.
- Impatto: il conteggio legacy del prefisso review restava piu' alto del necessario e rendeva piu' rumoroso il budget di tranche del cutover.
- Gravità: P2
- Steps to reproduce:
  1. Elencare i file sotto `App/SoloCodeApp/Sources/Panels/CodeReview/Store`.
  2. Contare i file `Rust*` Swift non-UI che inoltrano solo richieste a `ReviewCoreBridge`.
  3. Osservare che quattro file distinti restano legacy anche se la logica e' gia' lato Rust.
- Risultato attuale: il perimetro review portava quattro file Swift separati per bridge Rust minimi.
- Risultato atteso: i wrapper Rust-backed devono occupare il minor numero possibile di file Swift legacy, senza introdurre nuovi file Swift non-UI.
- Causa probabile: le tranche precedenti avevano migrato il comportamento verso Rust ma non avevano ancora consolidato il boundary Swift residuo.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - cambi di comportamento del panel
  - nuove API Rust
  - UI
- Moduli confinanti da verificare:
  - `CodeReviewPanelStore+ChatFindings.swift`
  - `CodeReviewPanelStore+History.swift`
  - `CodeReviewPanelStore+CompletionFinalization.swift`
  - `CodeReviewPanelStore+RustCompletionFinalization.swift`
- Test da aggiungere o aggiornare:
  - validation review con budget gate attivo
  - suite selettiva `SoloCodeAppTests` agganciata da `scripts/solocode-validate`
- Strategia di fix minimo:
  - riassorbire i bridge Rust-backed in file Swift gia' esistenti
  - eliminare i file wrapper ridondanti
  - aggiornare il progetto Xcode per rimuovere i reference orfani
- Verifica post-fix:
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustCompletionFinalization.swift,scripts/validate_rust_cutover_boundary.sh,"Solo Code.xcodeproj/project.pbxproj"`
- Commit previsto: `refactor(review): collapse rust-backed panel bridge files`

## Fix applicato
- riassorbiti i bridge chat/history nel file gia' esistente dello stesso flusso
- riassorbiti planning e patch-finalization bridge in `CodeReviewPanelStore+RustCompletionFinalization.swift`
- rimossi tre file Swift legacy dal prefisso review e puliti i relativi riferimenti nel `.pbxproj`

## Esito
- conteggio legacy del panel review ridotto da `36` a `33`
- nessuna nuova violazione Swift non-UI
- build e test selettivi review ancora verdi
