# 2026-03-12 - Review panel live run bootstrap helpers

## Modifiche
- aggiunto `CodeReviewPanelStore+LiveRunExecution.swift` con helper comuni per:
  - risoluzione `conversationId` del run
  - factory di `CodeReviewSessionState`
  - factory del provider review
  - attivazione dello stato run nel panel
- `startReview(...)` e `launchTargetedFixRun(...)` ora riusano lo stesso bootstrap helper.
- aggiunto `CodeReviewPanelLiveRunExecutionTests.swift`.
- aggiornato `Solo Code.xcodeproj/project.pbxproj` per includere il nuovo file app-side e il nuovo test.

## Validazione eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests`

## Note
- la build sui file toccati passa.
- l'esecuzione completa dei test resta bloccata dal problema ambientale LaunchServices/Xcode gia' noto.

## Esito
- il bootstrap live del panel e' meno duplicato
- il prossimo passo sull'orchestration live puo' concentrarsi su un helper comune invece che su due path separati
