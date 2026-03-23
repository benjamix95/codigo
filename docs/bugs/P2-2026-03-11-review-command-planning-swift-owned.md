# P2 — Review command planning ancora in Swift

## Sintomo
Il command bus del code review continuava a validare e normalizzare in Swift i comandi `start`, `configure`, `dismiss`, `comment` e le patch action prima dell'esecuzione.

## Impatto
- Logica business duplicata tra MCP/runtime e app bootstrap.
- Maggiore rischio di drift semantico tra code review pipeline Rust e deferred command loop.
- Possibili regressioni sui comandi validi ma normalizzati in modo diverso nei diversi entrypoint.

## Causa probabile
La migrazione precedente aveva spostato queue e persistence, ma il planning del command loop era rimasto dentro `SoloCodeApp+CodeReviewCommands.swift`.

## Fix applicato
- introdotto `review_core_command_plan` nel crate Rust
- aggiunto `review_command/` con planner dedicato
- collegato `ReviewCommandRustBridge` al bootstrap app
- aggiunta regressione sul loop per il comando `dismiss`

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests`

## Residuo
La mutazione snapshot offline e parte del sequencing patch restano ancora Swift-owned. Questa tranche chiude il planning/validation, non l'intero command executor.
