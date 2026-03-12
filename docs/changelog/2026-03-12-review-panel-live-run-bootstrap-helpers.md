# 2026-03-12 - Review panel live run bootstrap helpers

## Modifiche
- aggiunto `CodeReviewPanelStore+LiveRunExecution.swift` con helper comuni per:
  - risoluzione `conversationId` del run
  - factory di `CodeReviewSessionState`
  - factory del provider review
  - attivazione dello stato run nel panel
- `startReview(...)` e `launchTargetedFixRun(...)` riusano ora lo stesso bootstrap helper.
- aggiunto `CodeReviewPanelLiveRunExecutionTests.swift`.
- aggiornato `Solo Code.xcodeproj/project.pbxproj` per includere nuovo file app-side e nuovo test.

## Validazione eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests`

## Note
- la build sui file toccati passa.
- il run completo dei test resta bloccato dal problema ambientale LaunchServices/Xcode gia' presente in sessione.

## Esito
- il boundary live del panel ha meno bootstrap duplicato
- i prossimi step sulla migrazione dell'orchestration live possono concentrarsi su un solo helper comune
