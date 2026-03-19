# 2026-03-19 - Review panel runtime tranche 2 complete

## Modifiche
- eliminata dal panel la semantica prompt Swift di fallback in `ReviewPanelCoordinator`; il contenuto dei prompt panel-side e' ora delegato al review core Rust
- `startReview(...)` non bootstrapa piu' localmente `isRunning`, `runStartedAt`, `frozenTimerText` e `lastError` prima del reducer Rust
- mantenuti solo fallback espliciti di runtime unavailable o bridge failure, senza una seconda logica di dominio/parsing nel panel
- aggiornati i test panel-side sui prompt per richiedere esplicitamente il review core quando verificano contenuto semantico
- mantenute verdi le regressioni del panel runtime locale su:
  - session selection fallback
  - tab selection fallback
  - active chat thread fallback/runtime snapshot
  - live-run runtime unavailable

## Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `./scripts/build_rust_search_backend.sh`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadActivatesChatTab -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadSyncsRuntimeSnapshotWhenRustAvailable -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadFallsBackLocallyWhenRustUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests/testApplyChatConversationStateReconcilesActiveThreadIntoRuntimeSnapshot -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSetSelectedSessionFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSchedulePanelSessionBindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSelectHistoricalFindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSelectTabFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests/testCombinedPromptIncludesSelectedModeSections -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests/testCombinedPromptUsesBranchPromptWhenScopeIsBranch -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests/testChatContextPromptEnforcesBugSecurityAndMarkdownStructure -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests`

## Esito
- il panel runtime locale e' ora Rust-backed su:
  - run/chat reducer state
  - selection intents di sessione, finding, history, tab e active chat thread
  - prompt semantics panel-side
- Swift resta con adapter sottili per:
  - stream/provider execution
  - storage locale di conversation/thread
  - rendering/binding UI
- con questo batch la tranche 2 si considera chiusa; i prossimi step ricadono nelle tranche successive su command loop, MCP e patch workflow
