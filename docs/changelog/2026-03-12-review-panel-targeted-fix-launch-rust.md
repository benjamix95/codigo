# 2026-03-12 - Review panel targeted-fix bootstrap via Rust

## Modifiche
- `CodeReviewPanelStore+RustLaunchPlanning.swift` ora espone anche `planPanelTargetedFixLaunch(sourceSnapshot:)`.
- `CodeReviewPanelStore+TargetedFix.swift` usa il planner Rust per ottenere `fixSessionId` e config iniziale del run targeted fix.
- rimosso il path locale `makePanelTargetedFixSessionId(...)`.
- aggiunta regressione Swift su targeted-fix launch planning e su `rerunScopeTarget(for:)`.

## Validazione eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests`

## Note
- il build app-side passa; l'esecuzione dei test resta bloccata dal problema ambientale LaunchServices/Xcode gia' presente nella sessione.

## Esito
- il bootstrap del targeted fix converge sullo stesso planner Rust del launch review standard
- un altro pezzo di launch orchestration e' stato rimosso dal panel Swift
