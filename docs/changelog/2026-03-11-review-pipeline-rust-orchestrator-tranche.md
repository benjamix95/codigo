# 2026-03-11 — Review pipeline Rust orchestrator e snapshot canonico

## Modifiche
- aggiunto un nuovo sottosistema Rust `review_pipeline` con:
  - request/response FFI versionate
  - session store canonico
  - parsing scope/against-ref
  - task extraction
  - outcome classification
  - orchestratore step-based della review
- estesi gli entrypoint FFI in `Native/RustCore/src/ffi.rs`:
  - `review_core_run_pipeline`
  - `review_core_pipeline_start_session`
  - `review_core_pipeline_apply_callback_result`
  - `review_core_pipeline_get_snapshot`
  - `review_core_pipeline_resume`
  - `review_core_pipeline_cancel`
- introdotti i file Swift del bridge pipeline:
  - `ReviewPipelineRustModels`
  - `ReviewRuntimeAdapter`
  - `ReviewRuntimeAdapter+Execution`
  - `ReviewPipelineRustDriver`
  - `CodeReviewSessionState+RustSnapshot`
- `ReviewPipelineCoordinator.run` ora inoltra al driver Rust quando il review core è disponibile; il vecchio flusso Swift resta come fallback operativo.
- il coordinator è stato spezzato in `ReviewPipelineCoordinator.swift` e `ReviewPipelineCoordinator+Runtime.swift` per ridurre il file principale sotto il limite manutentivo.
- aggiornato `CodeReviewSessionState` per permettere la sincronizzazione dello snapshot canonico dal motore Rust.
- aggiornato `Solo Code.xcodeproj` per includere i nuovi file del bridge pipeline nel target `CoderEngine`.

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `scripts/build_rust_search_backend.sh`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests`

## Esito
- il path Rust governa ora il coordinator della review quando la libreria è caricata con successo
- il contratto osservabile degli snapshot verso panel/store resta compatibile
- i test regressione engine e app-side coinvolti sono verdi
- resta aperta la copertura benchmark della pipeline completa, documentata separatamente come bug P2
