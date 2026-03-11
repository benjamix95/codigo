# P2 — Il card della review mostrava naming tecnico di pipeline e numerazione poco intuitiva

## Bug Fix Record
- Categoria: B
- Bug: il card `Findings` esponeva testo tecnico (`Unified Review Pipeline`, `Publish Ready`, `5/6 steps`, copy con “pipeline”) invece di un linguaggio utente-facing.
- Sintomo: la review card rendeva visibili dettagli interni di implementazione e dava una percezione invertita/confusa della progressione.
- Impatto: UX più tecnica del necessario, disclosure di concetti interni, progressione poco chiara.
- Gravita': media.
- Steps to reproduce:
  1. Aprire il tab `Findings` durante una review.
  2. Osservare il card di stato con titolo e fase.
  3. Notare riferimenti a “pipeline” e numerazione `5/6 steps` non user-facing.
- Risultato attuale: il card deve usare copy di prodotto, senza riferimenti a pipeline, e una numerazione coerente per l’utente.
- Risultato atteso: titolo neutro, fasi leggibili (`Avvio`, `Controlli`, `Verifica`, `Preparazione fix`, `Risultati pronti`) e contatore `Fase X di 5`.
- Causa probabile: riuso diretto di fasi interne del review core anche nel layer UI.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Models/CodeReviewPanelModels.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Findings/ReviewPanelFindingDetail.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Findings/ReviewPanelFindingsTab.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Summary.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/*PipelineJobState*.swift`
  - `Native/RustCore/src/review_pipeline/phases.rs`
- Non-scope:
  - logica funzionale della review
  - workflow patch
  - storico persistence
- Test da aggiungere o aggiornare:
  - build smoke su layer UI + reducer Rust
- Strategia di fix minimo:
  - sostituire copy tecnico con label prodotto
  - rimappare il contatore visibile a una sequenza utente-facing
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_reduce::panel::tests::derive_review_panel_state_exposes_progressive_buckets`
  - `xcodebuild -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' build`
- Commit previsto: `fix(review): hide pipeline wording in review status card`
