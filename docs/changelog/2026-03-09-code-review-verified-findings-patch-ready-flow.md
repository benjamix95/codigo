# 2026-03-09 — Code Review verified findings con patch preview pronta

## Obiettivo
Rendere i finding `bugHunter` e `securityAuditor` del `Code Review` realmente azionabili dal tab `Findings`: solo finding verificati, detail completo e patch preview pronta prima dell’interazione utente.

## Modifiche
- `BugHunterWorkflowService` e `SecurityWorkflowService` ora avviano il review flow in modalità `analysis_only` e richiedono l’auto-prepare delle patch per i finding verificati
- `SoloCodeApp+CodeReviewDeferredCommands` auto-prepara le patch preview a fine scansione, in modo seriale e filtrato per origin, persistendo l’artifact nello snapshot live
- `CodeReviewFinding` conserva `expectedInvariant` e `reproOrReasoning`, così il detail e il prompt patch non perdono contesto di verifica
- `ReviewCandidateVerificationService` ricostruisce il candidate da finding mantenendo invariant/reasoning
- `ReviewPatchWorkflowService` costruisce il prompt patch includendo verification, remediation, invariant e repro/reasoning
- `ReviewPanelFindingDetail` è stato aggiornato con un redesign limitato al necessario:
  - sezioni esplicite per summary, verification, remediation, invariant/repro, patch preview e validation
  - stato errore patch visibile nel detail
  - azione `Fix` diretta dal panel quando esiste già la patch
- `ReviewPanelChatMessageContext` riconosce anche le card finding strutturate e le reindirizza al focus finding del panel

## File toccati
- `Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewFinding.swift`
- `Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewFinding+Factories.swift`
- `Engine/CoderEngine/Sources/CodeReview/Verification/ReviewCandidateVerificationService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterWorkflowService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/SecurityWorkflowService.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/SoloCodeApp+CodeReviewDeferredCommands.swift`
- `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Findings/ReviewPanelFindingDetail.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/ReviewPanelChatMessageContext.swift`
- `Tests/CoderEngineTests/CodeReview/CodeReviewFindingTests.swift`
- `Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsStartCommandServiceTests.swift`
- `Tests/SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests.swift`
- `Tests/SoloCodeAppTests/ReviewPanelChatMessageContextTests.swift`
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`

## Validazione
Eseguita con `xcodebuild` diretto perché `xcodebuildmcp` non è disponibile in questa sessione.

```bash
xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/CodeReviewFindingTests \
  -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests \
  -only-testing:SoloCodeAppTests/ReviewPanelChatMessageContextTests \
  -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests

xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests

xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests \
  -only-testing:SoloCodeAppTests/ReviewPanelChatMessageFactoryTests
```

Esito:
- `CodeReviewFindingTests`: 10 test verdi
- `VerifiedFindingsStartCommandServiceTests`: 6 test verdi
- `ReviewPanelChatMessageContextTests`: 3 test verdi
- `SoloCodeAppCodeReviewCommandLoopTests`: 4 test verdi
- `ReviewPatchWorkflowServiceTests`: 3 test verdi
- `ReviewPanelChatMessageFactoryTests`: 3 test verdi
