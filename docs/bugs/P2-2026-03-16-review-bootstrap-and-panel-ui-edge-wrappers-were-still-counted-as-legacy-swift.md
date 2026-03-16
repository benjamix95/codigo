# P2 - Bootstrap review e wrapper UI-edge del panel erano ancora dispersi in 5 file Swift legacy separati

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il dominio `CodeReview` manteneva ancora cinque file Swift legacy separati che non giustificavano ownership autonoma: tre wrapper bootstrap (`CodeReviewCommandLoopDriver`, `CodeReviewCommandRuntimeHooks`, `CodigoApp+CodeReviewCommandConfigure`) e due componenti panel-local UI-edge (`ReviewPanelCoordinator`, `CodeReviewPanelChatSessionStore`) ancora fuori da `Views/**`.
- Sintomo: l'audit strict review-scope continuava a contare file glue separati nel backlog non-UI anche quando la logica reale era gia' concentrata nel bridge review o nel panel rendering.
- Impatto: il backlog Swift non-UI del dominio review restava piu' alto del necessario e la migrazione perdeva tracciabilita' sui veri punti di ownership rimasti.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit strict review-scope dopo la tranche prompt precedente.
  2. Osservare `69` file Swift legacy non-UI, di cui `6` nel bootstrap app review e `16` nel panel app-side.
  3. Verificare che i tre file bootstrap sono solo helper del bridge/command loop e che coordinator/chat session store restano componenti panel-local.
- Risultato attuale: i tre helper bootstrap sono stati assorbiti in `ReviewCommandRustBridge.swift`; `ReviewPanelCoordinator.swift` e `ReviewPanelChatSessionStore.swift` sono stati ricollocati sotto `Views/**` come UI-edge coordinator/state del panel.
- Risultato atteso: questi wrapper non devono piu' comparire come file legacy separati nel backlog review.
- Causa probabile: tranche precedenti avevano spostato in Rust il runtime review ma lasciato file Swift piccoli e separati per comodita' di layering locale.
- Scope consentito:
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/*`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - engine `CodeReview`
  - `VerifiedFindingsCore`
  - handler MCP review
  - migrazione a Rust del coordinator panel o della chat session persistence
- Moduli confinanti da verificare:
  - command loop review
  - configure mutation persistita
  - panel prompt/chat regression
  - caricamento file nel progetto Xcode
- Test da aggiungere o aggiornare:
  - nessun nuovo test dedicato; usare le regression esistenti del command loop e del panel
- Strategia di fix minimo:
  - consolidare i tre helper bootstrap nel bridge review residuo
  - mantenere fallback locale per `configure` quando il core Rust non e' caricato nei test
  - ricollocare coordinator e chat session store nel subtree `Views/**`
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests`
  - audit strict review-scope
- Commit previsto: `fix(review): collapse bootstrap wrappers and move panel ui-edge state`

## Effetto osservato
- review strict prima del batch: `69` legacy non-UI
- review strict dopo il batch: `64` legacy non-UI
- riduzione per prefisso:
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview`: da `6` a `3`
  - `App/SoloCodeApp/Sources/Panels/CodeReview`: da `16` a `14`
