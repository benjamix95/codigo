# P3 - Il test di regressione sulla mode selection del panel review assumeva default obsoleti

## Bug Fix Record
- Categoria: C
- Bug: `testPanelModeSelectionAllowsMultiSelectAndSecondTapTurnsModeOff` assumeva che il panel partisse con la sola mode `.standard`, ma il contratto corrente del prodotto inizializza `selectedModes` con `.standard`, `.bugFinder` e `.securityAudit`.
- Sintomo: la suite `CodeReviewPanelSessionScopingTests` falliva sulla mode selection anche senza regressioni nel codice prodotto.
- Impatto: la validazione della tranche produceva un falso negativo e non distingueva un refactor innocuo da una regressione reale.
- Gravità: P3
- Steps to reproduce:
  1. Eseguire `xcodebuild test ... -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelModeSelectionAllowsMultiSelectAndSecondTapTurnsModeOff`.
  2. Osservare che il test si aspetta `.securityAudit` e `.bugFinder` disattivati all'avvio.
  3. Confrontare il contratto con `ReviewPanelProviderSelectionTests.testPanelDefaultsToFindingsTabAndUnifiedModes`.
- Risultato attuale: il test usa un'ipotesi di default non piu' valida.
- Risultato atteso: il test deve partire dal contratto attuale e verificare che il secondo tap spenga una mode mantenendo le altre.
- Causa probabile: il test non era stato riallineato dopo l'unificazione dei mode default del panel review.
- Scope consentito:
  - `Tests/SoloCodeAppTests/CodeReviewPanelSessionScopingTests.swift`
- Non-scope:
  - codice prodotto del panel
  - configurazione provider
  - runtime Rust
- Moduli confinanti da verificare:
  - `ReviewPanelProviderSelectionTests`
  - `CodeReviewPanelChatStateDeferralTests`
- Test da aggiungere o aggiornare:
  - aggiungere una regression suite piccola dedicata alla mode selection corrente
- Strategia di fix minimo:
  - mantenere invariato il codice prodotto
  - evitare di toccare `CodeReviewPanelSessionScopingTests.swift` perche' e' gia' oltre il limite dimensionale del repo
  - aggiungere una suite focalizzata che verifichi il contratto attuale di mode selection
- Verifica post-fix:
  - `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests`
- Commit previsto: `refactor(review): collapse panel modes and chat threads store file`
