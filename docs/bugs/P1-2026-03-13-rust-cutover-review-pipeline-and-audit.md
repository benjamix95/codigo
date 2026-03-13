# P1 - Review pipeline e audit engine mantenevano ancora orchestration Swift fuori dal core Rust

## Bug Fix Record
- Categoria: A - Critico
- Bug: `ReviewPipelineCoordinator` conservava un intero fallback Swift della pipeline review e `CodeReviewAuditService` continuava a eseguire localmente la business logic audit quando il core Rust non era disponibile o non copriva il tool.
- Sintomo: la review poteva continuare a funzionare con semantica Swift locale, nascondendo il fatto che il cutover Rust non fosse effettivo.
- Impatto: ownership di dominio duplicata, maggiore rischio di drift tra pipeline Rust, audit Rust e comportamento osservabile del prodotto.
- Gravita': alta
- Steps to reproduce:
  1. Disabilitare il review core Rust con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`.
  2. Avviare una review pipeline dal motore o eseguire tool audit review.
  3. Osservare che il coordinatore e il servizio audit ricadevano su logica Swift locale invece di fallire in modo esplicito.
- Risultato attuale: pipeline review e audit devono essere Rust-owned; se Rust non e' disponibile il motore deve fallire esplicitamente o riportare tool non supportato, senza eseguire logica Swift sostitutiva.
- Risultato atteso: `ReviewPipelineCoordinator` inoltra solo al driver Rust; `CodeReviewAuditService` usa solo il bridge Rust per i tool non-meta e produce risultato esplicito per `unsupported` / `unavailable`.
- Causa probabile: tranche di migrazione precedenti avevano lasciato reti di sicurezza Swift per rollout incrementale.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator.swift`
  - `Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift`
  - `Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift`
- Non-scope:
  - porting completo di tutti i tool audit nel crate Rust
  - refactor UI del review panel
  - rimozione di tutta la logica meta `runProfile` / `correlateResults`
- Moduli confinanti da verificare:
  - `ReviewPipelineRustDriver`
  - `ReviewCoreBridge`
  - `CodeReviewAuditService+Correlation`
  - `CodeReviewMultiSwarmProvider`
- Test da aggiungere o aggiornare:
  - pipeline fallisce esplicitamente se il core Rust e' disabilitato
  - i test pipeline che richiedono esecuzione reale usano la libreria Rust se disponibile
  - build engine verde con il nuovo contratto Rust-only
- Strategia di fix minimo:
  - eliminare il ramo fallback Swift in `ReviewPipelineCoordinator.run`
  - lasciare ai tool audit meta locali solo funzioni di composizione, ma rimuovere l'esecuzione audit locale per i tool effettivi
  - restituire outcome espliciti `unsupported` o `unavailable` invece di usare heuristics Swift
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml -- --nocapture`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`
- Commit previsto: `refactor(rust-cutover): require rust review pipeline and audit bridge`

## Note
- Questo slice rende visibile il gap residuo dei tool audit non ancora implementati in Rust, ma elimina il drift nascosto causato dal fallback Swift locale.
