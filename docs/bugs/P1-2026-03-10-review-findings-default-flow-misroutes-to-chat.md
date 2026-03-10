# P1 — review esplicita dalla Home instradata in chat e findings pubblicati troppo presto

## Bug Fix Record
- Categoria: A
- Bug: le richieste esplicite di code review, bug hunt e security audit dalla Home/main chat venivano trattate come stream primario in chat invece che come pipeline findings-first nel panel dedicato.
- Sintomo: il comando partiva nella main chat o nel tab chat del review panel; il tab `Findings` non era la home del run e i finding apparivano senza un lifecycle professionale `verifica -> patch preview -> publish`.
- Impatto: UX fuorviante, contratto falso sul tempo di analisi, assenza di gating enterprise-grade su findings bug/security.
- Gravità: alta
- Steps to reproduce:
  1. Aprire la Home/main chat.
  2. Inviare una richiesta esplicita come “fai una review di sicurezza del diff” o “fai bug hunt”.
  3. Osservare che il flusso parte come output chat invece che come pipeline findings-first.
  4. Osservare che il panel review non usa di default `Findings` come superficie primaria.
- Risultato attuale: routing verso runtime review con stream/chat come output principale e findings non governati da uno stato strutturato di publish readiness.
- Risultato atteso: apertura automatica del panel Code Review sul tab `Findings`, pipeline unificata `standard + bugFinder + securityAudit`, job card con progress/gate/tool counters e pubblicazione solo dei finding `verified + patch ready`.
- Causa probabile: il path `makeAutoCodeReviewRequest -> sendMessage` privilegiava il runtime code review della chat; `startReview` forzava `selectedTab = .chat` e costruiva sempre action output chat-centric.
- Scope consentito: routing main chat review, store/view del Code Review panel, shared status payload verified findings, snapshot BugHunter, test review/status correlati, documentazione bug/changelog.
- Non-scope: refactor generale della chat, redesign completo del detail finding, cambi al patch engine oltre il gating necessario.
- Moduli confinanti da verificare:
  - `AutoCodeReviewRouting`
  - `CodeReviewPanelStore`
  - `ReviewPanelLifecycle`
  - `VerifiedFindingsStatusService`
  - `BugHunterHandler`
- Test da aggiungere o aggiornare:
  - `SoloCodeAppTests/AutoCodeReviewRoutingTests`
  - `SoloCodeAppTests/ReviewPanelProviderSelectionTests`
  - `SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
  - `CoderEngineTests/VerifiedFindingsStatusServiceTests`
  - `CoderEngineTests/BugHunterHandlerTests`
- Strategia di fix minimo:
  - intercettare il routing auto-review prima della creazione dello stream assistant in main chat
  - aprire il panel review via launch request condivisa
  - rendere `Findings` tab di default e bundle modes di default `standard + bugFinder + securityAudit`
  - derivare uno stato pipeline strutturato con progress, tools e gate
  - filtrare i finding visibili ai soli `verified + patch preview pronta`
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/AutoCodeReviewRoutingTests -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests -only-testing:CoderEngineTests/VerifiedFindingsStatusServiceTests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/BugHunterHandlerTests`
- Commit previsto: `fix(review): route explicit review requests to findings-first panel`

## Note
- Il progetto non registra automaticamente i nuovi file Swift nei target Xcode. Il fix è stato quindi ricondotto nei file già inclusi nei target per evitare una patch parzialmente compilabile.
