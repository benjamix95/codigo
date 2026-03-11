# P2 — La dedup identity restava duplicata tra Swift e Rust con rischio di drift semantico

## Bug Fix Record
- Categoria: B
- Bug: `FindingIdentityService.findDuplicate(candidate:existing:)` continuava a usare solo la logica Swift, mentre la sync `VerifiedFindings` era gia' passata dal core Rust.
- Sintomo: la dedup locale e la dedup usata dalla pipeline potevano divergere su score, tie-break e scelta del match migliore.
- Impatto: rischio di risultati incoerenti tra sync, replay storico e verifica locale dei finding duplicati, con possibili regressioni difficili da diagnosticare.
- Gravita': media, ma in area fragile perche' tocca identity, dedup e coerenza del review core.
- Steps to reproduce:
  1. Avere un candidato con match approssimato su stesso file/categoria ma titolo diverso.
  2. Eseguire dedup locale via `FindingIdentityService.findDuplicate`.
  3. Eseguire la stessa valutazione attraverso la sync Rust.
  4. Con logiche duplicate, il rischio e' ottenere tie-break o score diversi.
- Risultato attuale: la ricerca del duplicato deve usare lo stesso core Rust gia' adottato dal path di sync, con fallback Swift solo se la libreria non e' disponibile.
- Risultato atteso: stesso input, stesso risultato semantico su dedup locale e sync del review core.
- Causa probabile: migrazione Rust incompleta; la sync era stata portata sul core nativo, ma `FindingIdentityService` era rimasto con implementazione autonoma in Swift.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/FindingIdentityService.swift`
  - `Native/RustCore/src/review_identity.rs`
  - `Native/RustCore/src/ffi.rs`
  - test `FindingIdentityServiceTests`
- Non-scope:
  - orchestrazione `ReviewPipelineCoordinator`
  - UI/store SwiftUI
  - query SQL dello storico
- Moduli confinanti da verificare:
  - `VerifiedFindingsSessionSyncService`
  - `HistoricalFindingsQueryService`
  - `ReviewCoreBridge`
- Test da aggiungere o aggiornare:
  - test di parity Swift/Rust su `FindingIdentityService`
  - test Rust unitari sul tie-break del miglior match
- Strategia di fix minimo:
  - esporre un entrypoint FFI stretto `review_core_find_duplicate`
  - delegare `FindingIdentityService.findDuplicate` al core Rust quando disponibile
  - mantenere il fallback Swift come rete di sicurezza
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindings/FindingIdentityServiceTests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SearchEngineBackendTests/testReviewCoreBridgeLoadedStateReturnsVersionWhenLibraryPathIsForced`
- Commit previsto: `perf(review): unify identity dedup through rust review-core`
