# 2026-03-12 - ReviewSessionRegistry live mutations via Rust

## Modifiche
- `ReviewSessionRegistry` usa ora il mutator Rust per `applyFix`, `dismissFinding` e `addComment`.
- aggiunto helper interno `mutateLiveSession(...)` che:
  - legge lo snapshot live
  - invoca `review_core_command_mutate_snapshot`
  - riapplica lo snapshot canonico allo state actor
  - aggiorna il registry
- `CodeReviewSessionState+RustSnapshot.swift` resta il punto comune per riapplicare lo snapshot canonico.
- aggiunte regressioni in `ReviewSessionRegistryTests.swift` per dismiss e comment live.

## Validazione eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewSessionRegistryTests`

## Note
- la build sui file toccati prosegue oltre il delta del registry.
- l'ambiente continua a mostrare instabilita' LaunchServices/Xcode al launch dei test macOS, quindi il run non e' affidabile end-to-end in questa sessione.

## Esito
- il registry live converge sullo stesso mutator Rust gia' usato dagli altri boundary review
- un altro doppio path semantico live-vs-fallback e' stato eliminato
