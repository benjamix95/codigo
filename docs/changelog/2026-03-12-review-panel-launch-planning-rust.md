# 2026-03-12 - Review panel launch bootstrap planning via Rust

## Modifiche
- esteso `review_command::planner` per generare `sessionId` prefissati e univoci quando `session_id` manca.
- aggiunto `CodeReviewPanelStore+RustLaunchPlanning.swift` come adapter panel-side verso `review_core_command_plan`.
- `CodeReviewPanelStore+Launch.swift` ora ottiene `sessionId` e `SessionConfig` iniziale dal planner Rust, invece di costruirli localmente.
- `rerunSession(...)` usa ora lo stesso boundary helper del launch planning per ricostruire lo scope del replay, evitando altra logica in-line nel file launch.
- rimosse dal panel le helper locali dedicate a generation/config bootstrap.
- aggiunto test Swift su `planPanelReviewLaunch()` e test Rust sul prefisso generato.
- aggiunto test Swift su `rerunScopeTarget(for:)` per bloccare il mapping dello scope di rerun.
- aggiornato `Solo Code.xcodeproj/project.pbxproj` per includere il nuovo file Swift nel target app.

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests`

## Note
- la suite Rust e' verde.
- il build app-side passa fino al launch dei test; il run resta soggetto al problema ambientale LaunchServices/Xcode gia' presente nella sessione.

## Esito
- il launch bootstrap del panel converge sul planner Rust gia' usato dal command boundary
- un altro blocco di orchestration review e' stato rimosso dal panel Swift
