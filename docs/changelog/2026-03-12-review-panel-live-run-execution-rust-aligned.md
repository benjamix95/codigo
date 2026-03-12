# 2026-03-12 - Review panel live run execution helpers

## Modifiche
- `CodeReviewPanelStore+LiveRunExecution.swift` centralizza ora anche:
  - `completePanelRun`
  - `failPanelRun`
  - `runPanelReview`
- `CodeReviewPanelStore+Launch.swift` e `CodeReviewPanelStore+TargetedFix.swift` usano lo stesso helper per l’invocazione del run live e le transizioni base del lifecycle.
- aggiornati i test `CodeReviewPanelLiveRunExecutionTests.swift` per coprire complete/fail del run.

## Validazione eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests`

## Note
- il build sui file toccati passa.
- l’esecuzione completa resta bloccata in ambiente dal problema LaunchServices/Xcode gia' presente in sessione.

## Esito
- un altro blocco di orchestration live e' stato concentrato in un helper unico del panel
- il prossimo passo puo' mirare piu' direttamente al cutover del `coordinator.runReview(...)`
