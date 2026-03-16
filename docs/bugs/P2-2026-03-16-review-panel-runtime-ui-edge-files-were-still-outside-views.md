# P2 - Cinque file runtime UI-edge del panel review erano ancora fuori da `Views/**`

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: cinque file panel-side che gestiscono output/chat/run locale del tab review restavano ancora nel subtree `Store/`, quindi venivano contati come legacy non-UI nonostante fossero controller/state di bordo del panel.
- Sintomo: `CodeReviewPanelStore+ActionOutput.swift`, `CodeReviewPanelStore+ChatFindings.swift`, `CodeReviewPanelStore+ChatMessages.swift`, `CodeReviewPanelStore+CompletionFinalization.swift` e `CodeReviewPanelStore+LiveRunExecution.swift` comparivano ancora nel backlog review app-side.
- Impatto: il backlog `App/SoloCodeApp/Sources/Panels/CodeReview` restava gonfiato da file panel-local che non rappresentano ownership di dominio review core.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit strict review-scope dopo il batch precedente.
  2. Osservare che il prefisso panel-side vale ancora `14` file legacy non-UI.
  3. Verificare che i cinque file citati operano su chat bubble/output/runtime del panel, non su domain core engine-side.
- Risultato attuale: i cinque file sono ora ricollocati sotto `Views/Runtime/` e rientrano nel boundary UI-side del panel.
- Risultato atteso: il backlog panel-side deve riflettere solo le ownership Swift non-UI ancora realmente da migrare o eliminare.
- Causa probabile: il panel review era stato spezzato inizialmente per responsabilita' tecniche locali, ma alcune estensioni di store erano rimaste nel subtree `Store/` anche dopo che il loro ruolo era diventato UI-edge.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/*`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - bootstrap app review
  - engine `CodeReview`
  - `VerifiedFindingsCore`
  - handler MCP review
- Moduli confinanti da verificare:
  - panel chat state deferral
  - live run execution
  - chat session store
  - rendering/structured content panel
- Test da aggiungere o aggiornare:
  - nessun test nuovo; usare regression panel gia' presenti
- Strategia di fix minimo:
  - ricollocare i cinque file sotto `Views/Runtime/`
  - aggiornare il progetto Xcode senza cambiare i simboli pubblici
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests`
  - audit strict review-scope
- Commit previsto: `fix(review): move panel runtime ui-edge files under views`

## Effetto osservato
- review strict prima del batch: `64` legacy non-UI
- review strict dopo il batch: `59` legacy non-UI
- riduzione per prefisso:
  - `App/SoloCodeApp/Sources/Panels/CodeReview`: da `14` a `9`
