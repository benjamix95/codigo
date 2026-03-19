# P2 - Il review panel manteneva ancora una semantica prompt Swift di fallback e bootstrap locale del run

## Bug Fix Record
- Categoria: B
- Bug: il panel review manteneva ancora due ownership Swift residue nel runtime locale:
  - un fallback semantico Swift per i prompt in `ReviewPanelCoordinator`
  - un bootstrap locale del run in `startReview(...)` che impostava `isRunning`, timer ed errore prima del reducer Rust.
- Sintomo: anche con reducer Rust gia' owner di run/chat state e selection intents, Swift conservava una seconda semantica per prompt e pre-run lifecycle.
- Impatto: il panel runtime non era ancora chiudibile come tranche Rust-backed, perche' restavano due path di decisione locale non necessari.
- Gravita': media.
- Steps to reproduce:
  1. Invocare i prompt panel-side via `ReviewPanelCoordinator`.
  2. Verificare la presenza di `fallbackPrompt(...)` con logica semantica locale.
  3. Avviare `startReview(...)` e notare che il run entra in stato attivo con assegnazioni locali prima del path Rust `applyPanelRunStart(...)`.
- Risultato attuale: il panel mantiene una semantica prompt locale e un pre-bootstrap run locale in Swift.
- Risultato atteso: la semantica del prompt deve vivere solo nel review core Rust; il run lifecycle del panel deve entrare nel path Rust-first senza bootstrap locale ridondante.
- Causa probabile: le tranche precedenti avevano spostato state e selection nel reducer Rust, ma avevano lasciato invariati due residui a basso rischio rimasti nel coordinator e nel launch path.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Shared/ReviewPanelCoordinator.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+LiveRunExecution.swift`
  - test panel-side su prompt e live-run
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - patch workflow
  - command loop review
  - MCP review/security/bughunter
  - persistenza `ReviewPanelChatSessionStore`
- Moduli confinanti da verificare:
  - `CodeReviewPanelValidationTests`
  - `ReviewPanelChatStructuredContentTests`
  - `CodeReviewPanelLiveRunExecutionTests`
  - fallback locali gia' verdi su session/tab/thread selection
- Test da aggiungere o aggiornare:
  - test prompt panel-side richiedono esplicitamente il review core quando verificano il contenuto semantico del prompt
  - suite live-run deve continuare a passare con il path Rust-first e con il fallback di runtime unavailable
- Strategia di fix minimo:
  - eliminare `fallbackPrompt(...)` dal coordinator
  - delegare la costruzione del prompt solo al review core Rust
  - rimuovere il bootstrap locale di `isRunning`, timer ed errore in `startReview(...)`
  - mantenere solo il fallback esplicito `runtime unavailable` quando il bridge non e' disponibile
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `./scripts/build_rust_search_backend.sh`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadActivatesChatTab -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadSyncsRuntimeSnapshotWhenRustAvailable -only-testing:SoloCodeAppTests/ReviewPanelChatSessionStoreTests/testPanelCreateAndSelectChatThreadFallsBackLocallyWhenRustUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests/testApplyChatConversationStateReconcilesActiveThreadIntoRuntimeSnapshot -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSetSelectedSessionFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSchedulePanelSessionBindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSelectHistoricalFindingFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testSelectTabFallsBackLocallyWhenRustIntentUnavailable -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests/testCombinedPromptIncludesSelectedModeSections -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests/testCombinedPromptUsesBranchPromptWhenScopeIsBranch -only-testing:SoloCodeAppTests/ReviewPanelChatStructuredContentTests/testChatContextPromptEnforcesBugSecurityAndMarkdownStructure -only-testing:SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests`
- Commit previsto: `refactor(review-panel): finish panel runtime rust cutover`

## Effetto osservato
- il coordinator del panel resta solo adapter di stream/provider e non porta piu' una semantica prompt locale parallela
- `startReview(...)` non entra piu' in stato running tramite bootstrap locale prima del reducer Rust
- con questo batch il panel runtime locale puo' essere considerato chiuso come tranche Rust-backed, lasciando ai batch successivi command loop/MCP/patch workflow e il residuale adapter/provider bridge
