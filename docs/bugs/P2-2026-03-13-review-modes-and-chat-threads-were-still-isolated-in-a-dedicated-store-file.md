# P2 - Le mode selection e il routing dei chat thread del panel review restavano isolate in un file store dedicato

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewPanelStore+ModesAndChatThreads.swift` restava un file Swift non-UI dedicato nel panel review pur contenendo solo helper di mode selection, session key e sincronizzazione dei thread chat del panel.
- Sintomo: la logica store per selezione modalita', thread attivo e applicazione differita della conversazione chat viveva ancora in un extension separato.
- Impatto: il perimetro Swift non-UI del panel review restava piu' frammentato del necessario e il backlog legacy non scendeva nonostante il comportamento fosse gia' confinato nel layer store.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ModesAndChatThreads.swift`.
  2. Verificare che il file contenga solo ownership locale del panel store per mode selection e thread chat.
  3. Notare che il file compare ancora nel conteggio Swift non-UI del dominio review.
- Risultato attuale: mode selection e chat-thread state vivevano ancora in un file store dedicato.
- Risultato atteso: questi helper devono essere consolidati in un extension store gia' esistente, senza mantenere un file standalone aggiuntivo.
- Causa probabile: tranche precedenti avevano drenato wrapper piu' urgenti ma non avevano ancora collassato questo extension store residuo.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - boundary Rust del panel review
  - UI SwiftUI/AppKit
  - servizi engine e MCP
- Moduli confinanti da verificare:
  - `CodeReviewPanelStore+ChatFindings.swift`
  - `CodeReviewPanelChatSessionStore`
  - `CodeReviewPanelChatStateDeferralTests`
  - `CodeReviewPanelSessionScopingTests`
- Test da aggiungere o aggiornare:
  - `ReviewPanelChatSessionStoreTests`
- Strategia di fix minimo:
  - assorbire l'intero contenuto del file in `CodeReviewPanelStore+ChatFindings.swift`
  - mantenere invariata la semantica di `handleIncomingChatConversation`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `xcodebuild build -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -derivedDataPath "$TMPDIR/review-modes-chat-tranche-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-modes-chat-tranche-source-packages"`
  - `./scripts/bootstrap_test_bundles.sh "$TMPDIR/review-modes-chat-tranche-derived-data/Build/Products/Debug"`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath "$TMPDIR/review-modes-chat-tranche-derived-data" -clonedSourcePackagesDirPath "$TMPDIR/review-modes-chat-tranche-source-packages" -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelStoreRestoresCachedChatSessionState -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests/testPanelDefaultsToFindingsTabAndUnifiedModes`
  - `scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ModesAndChatThreads.swift --format text`
- Commit previsto: `refactor(review): collapse panel modes and chat threads store file`

## Fix applicato
- helper di mode selection, chat session key e gestione dei thread spostati in `CodeReviewPanelStore+ChatFindings.swift`
- mantenuta la logica di stale conversation detection nel perimetro store
- rimosso `CodeReviewPanelStore+ModesAndChatThreads.swift` dal filesystem e dal progetto Xcode
- aggiunte regression mirate in `ReviewPanelChatSessionStoreTests.swift` per mode selection e chat thread actions del panel

## Esito
- il panel review riduce di un'altra unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
- la copertura esistente su deferral chat e scoping sessione resta il riferimento di regressione
