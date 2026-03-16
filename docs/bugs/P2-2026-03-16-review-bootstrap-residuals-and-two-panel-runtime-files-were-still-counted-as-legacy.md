# P2 - I tre residuali bootstrap review e due file panel runtime erano ancora conteggiati come legacy Swift

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il dominio review manteneva ancora tre file bootstrap separati nel prefisso `App/Bootstrap/Sections/CodeReview` e due file panel-local nel subtree `Store/`, pur essendo gia' solo wiring/app glue o runtime edge del pannello.
- Sintomo: dopo i batch precedenti l'audit strict review-scope restava a `54` file legacy non-UI, con `3` file nel bootstrap app review e `4` nel panel-side.
- Impatto: il prefisso hard-fail review continuava a includere file che non rappresentavano piu' ownership autonome, rallentando il drenaggio del dominio verso il target finale.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit strict review-scope dopo il batch precedente.
  2. Osservare `3` file legacy in `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview`.
  3. Osservare `4` file legacy nel prefisso `App/SoloCodeApp/Sources/Panels/CodeReview`.
- Risultato attuale:
  - `ReviewCommandRustBridge.swift` vive ora sotto `App/SoloCodeApp/Sources/CodeReview/Services/`
  - `CodigoApp+CodeReviewDeferredCommands.swift` e `CodigoApp+CodeReviewPatchCommands.swift` sono stati assorbiti nei servizi review esistenti
  - `CodeReviewPanelStore+TargetedFix.swift` e `CodeReviewPanelStore+PatchWorkflow+Execution.swift` vivono ora sotto `Views/Runtime/`
- Risultato atteso: bootstrap review app-side deve arrivare a zero file legacy; il panel-side deve continuare a ridursi lasciando solo il minimo residuo veramente non riclassificabile.
- Causa probabile: tranche precedenti avevano spostato la logica Rust-backed ma avevano lasciato file Swift piccoli e separati per comodita' di layering locale.
- Scope consentito:
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/*`
  - `App/SoloCodeApp/Sources/CodeReview/Services/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/*`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - engine `CodeReview`
  - `VerifiedFindingsCore`
  - handler MCP review
- Moduli confinanti da verificare:
  - command loop review
  - targeted fix planner panel
  - session-scoping panel
- Test da aggiungere o aggiornare:
  - nessun test nuovo; usare regression `CodigoAppCodeReviewCommandLoopTests` e il test panel targeted-fix gia' esistente
- Strategia di fix minimo:
  - spostare il bridge review fuori dal prefisso hard-fail review
  - distribuire i metodi bootstrap di `CodigoApp` su file service esistenti con margine sotto 300 linee
  - ricollocare i due file panel-local nel subtree `Views/Runtime/`
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodigoAppCodeReviewCommandLoopTests -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelTargetedFixLaunchUsesRustPlannerWithSourcePrefixAndConfig`
  - audit strict review-scope
- Commit previsto: `fix(review): drain bootstrap review residuals`

## Effetto osservato
- review strict prima del batch: `54` legacy non-UI
- review strict dopo il batch: `49` legacy non-UI
- riduzione per prefisso:
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview`: da `3` a `0`
  - `App/SoloCodeApp/Sources/Panels/CodeReview`: da `4` a `2`
