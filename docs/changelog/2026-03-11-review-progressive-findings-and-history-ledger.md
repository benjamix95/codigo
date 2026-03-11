# 2026-03-11 — Review progressive findings and history ledger

## Cosa cambia

- Il reducer Rust del panel review ora espone bucket progressivi distinti:
  - `liveCandidateIds`
  - `verifiedFindingIds`
  - `publishReadyFindingIds`
- Il panel SwiftUI non mostra piu soltanto finding `publish-ready`: il tab `Findings` ora rende candidati live, finding verificati e finding con patch pronta in sezioni separate.
- Il job card review usa anche il `phaseLedger` canonico per mostrare la progressione delle 6 fasi nel panel.
- Il path standard del panel auto-prepara la patch per i finding verificati e patchabili a fine review, invece di dipendere solo dai workflow deferred/command bus.
- `Findings History` usa il `fileLedger` dello snapshot come sorgente primaria del live board; `TaskActivity` resta fallback secondario.
- Il bridge di persistenza review verso il core Rust ora fa fallback all’encoder/decoder Swift se la normalizzazione Rust non riesce in ambiente test.

## File/aree toccate

- Core Rust:
  - `Native/RustCore/src/review_pipeline/*`
  - `Native/RustCore/src/review_reduce/*`
  - `Native/RustCore/src/review_patch/runtime.rs`
- Engine Swift:
  - modelli snapshot review e ledger condivisi
  - persistence adapter review Rust
- App SwiftUI:
  - store summary/history live/completion finalization
  - viste findings e job card
  - project wiring per nuovi file
- Test:
  - `ReviewPanelProviderSelectionTests`
  - `ReviewPanelFindingsHistoryLiveBoardTests`
  - `ReviewPanelFindingsHistoryTests`

## Verifica eseguita

- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testRefreshHistoricalFindingsReadsPersistedWorkspaceHistory`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryLiveBoardTests -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`

## Note

- Un lancio aggregato di `xcodebuild test` sul gruppo completo dei test review/history ha mostrato un crash interno di Xcode (`IDELaunchServicesLauncher childPID > 0`) non riproducibile nei lanci targettizzati; i test targettizzati che coprono le aree modificate risultano verdi.
