# P1 - Le risposte Rust della sessione review non erano ancora sempre decodificabili da Swift

## Bug Fix Record
- Categoria: A
- Bug: la nuova tranche `Session + Registry` usava entrypoint Rust per le mutate review, ma alcune risposte `review_core_session_apply_action` restituivano eventi non compatibili col decoder Swift.
- Sintomo: `applyFix`, `dismissFinding`, `addComment` e `updateConfig` potevano fallire chiusi nel `CodeReviewSessionState` anche con dylib Rust presente, lasciando lo snapshot locale invariato.
- Impatto: la session state review non era ancora veramente Rust-owned sui path command-like; il fail-closed scattava per incompatibilita' di payload e non per indisponibilita' reale del runtime.
- Gravita': alta, perche' tocca stato condiviso, lifecycle dei finding e configurazione di sessione.
- Steps to reproduce:
  1. Inizializzare `CodeReviewSessionState` con review core Rust caricato.
  2. Aggiungere un finding e invocare `applyFix`, `dismissFinding` o `addComment`.
  3. Osservare `CodeReviewSessionStateTests` prima del fix: risultato `false` e snapshot invariato.
  4. Inviare `configure` e osservare che `config` resta ai default.
- Risultato attuale: il bridge Swift riceveva snapshot Rust non sempre decodificabili.
- Risultato atteso: tutte le mutate session/registry devono ritornare snapshot canonici decodificabili da Swift, con eventi e metadata coerenti al contratto `CodeReviewSessionEvent`.
- Causa probabile:
  - i mutator command Rust serializzavano `events.timestamp` come stringa invece che come `Date` reference-seconds compatibile con Swift
  - `config_updated` serializzava `metadata` con `Int/Bool`, mentre Swift legge `[String: String]`
  - i test live `ReviewSessionRegistryTests` risolvevano il dylib dal `cwd`, producendo skip ambientali non affidabili
- Scope consentito:
  - `Native/RustCore/src/review_command/*`
  - `Native/RustCore/src/review_session/*`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Session/*`
  - `Tests/CoderEngineTests/CodeReview/*`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - provider orchestration
  - pipeline runtime completo
  - panel runtime app-side
  - patch workflow end-to-end
- Moduli confinanti da verificare:
  - `CodeReviewSessionStateTests`
  - `ReviewSessionRegistryTests`
  - `ReviewPipelineCoordinatorTests`
  - `CodeReviewMultiSwarmProviderTests`
- Test da aggiungere o aggiornare:
  - regressioni Rust sui timestamp/comment metadata in `review_command::mutator`
  - setup test condiviso per il dylib review core
  - test live `ReviewSessionRegistryTests` senza skip
- Strategia di fix minimo:
  - introdurre entrypoint Rust dedicati per `newSnapshot`, `applyAction`, `deriveView`, `applyRegistryAction`
  - instradare `CodeReviewSessionState` e `ReviewSessionRegistry` verso snapshot canonici Rust
  - normalizzare `timestamp` numerici e `metadata` stringificati nel mutator command Rust
  - usare il resolver test condiviso del dylib anche nei test registry live
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewSessionStateTests -only-testing:CoderEngineTests/ReviewSessionRegistryTests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewSessionStateTests -only-testing:CoderEngineTests/ReviewSessionRegistryTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests/testParsesStructuredWorkerTasksFromTaggedSections -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests/testTaskExtractionFallsBackToChecklistBullets`
- Commit previsto: `refactor(review-session): route session state through rust core`

## Effetto osservato
- Il layer `Session + Registry` usa ora snapshot canonici Rust anche sulle mutate live.
- I test live di `ReviewSessionRegistry` non saltano piu' per path dylib dipendenti dal `cwd`.
- Il boundary Swift resta fail-closed solo quando il review core e' davvero indisponibile, non per payload incompatibili.
