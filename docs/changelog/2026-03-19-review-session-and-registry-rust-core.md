# 2026-03-19 - Review session e registry su core Rust

## Modifiche
- aggiunto il modulo Rust `review_session` con entrypoint:
  - `review_core_session_snapshot_new`
  - `review_core_session_apply_action`
  - `review_core_session_derive_view`
  - `review_core_registry_apply_action`
- introdotto `ReviewSessionRustBridge.swift` e instradato `CodeReviewSessionState` verso snapshot canonici Rust per lifecycle, findings, candidate/patch e config
- `ReviewSessionRegistry` usa il reducer Rust anche per mutate live/config sulla sessione registrata
- normalizzati nel mutator command Rust:
  - `events.timestamp` in reference-seconds numerici
  - `config_updated.metadata` come dizionario stringificato compatibile con `CodeReviewSessionEvent`
- aggiornati i test `CodeReviewSessionStateTests` e `ReviewSessionRegistryTests` per usare il resolver condiviso del dylib review core, eliminando gli skip ambientali del path live

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewSessionStateTests -only-testing:CoderEngineTests/ReviewSessionRegistryTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewSessionStateTests -only-testing:CoderEngineTests/ReviewSessionRegistryTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests/testParsesStructuredWorkerTasksFromTaggedSections -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests/testTaskExtractionFallsBackToChecklistBullets`

## Esito
- `Session + Registry` sono ora coperti dal boundary Rust reale, senza fallback Swift sui path di mutazione immediata
- le suite live `CodeReviewSessionStateTests` e `ReviewSessionRegistryTests` sono verdi senza skip
- i moduli confinanti `ReviewPipelineCoordinator` e parsing/task extraction del provider restano verdi dopo il rebinding del session state
