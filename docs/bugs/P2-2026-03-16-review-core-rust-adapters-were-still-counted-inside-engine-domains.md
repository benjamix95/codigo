# P2 - Gli adapter review-core Rust erano ancora conteggiati dentro i domini engine review

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: cinque file gia' Rust-backed o chiaramente bootstrap adapter vivevano ancora nei prefissi hard-fail `Engine/CoderEngine/Sources/CodeReview` e `Engine/CoderEngine/Sources/VerifiedFindingsCore`, pur non essendo piu' ownership di business logic primaria del dominio.
- Sintomo: dopo il batch precedente l'audit strict review-scope restava a `42` file legacy non-UI, con adapter review-core ancora mescolati ai layer engine/domain.
- Impatto: il debito residuo review appariva piu' alto del reale e rendeva piu' difficile separare cosa resta davvero da portare in Rust da cosa e' gia' solo host/DTO/bridge del review core.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit strict review-scope dopo il batch `review-mcp-host-zero-and-diff-summary-rust`.
  2. Osservare file adapter come `ReviewPipelineRustDriver.swift`, `ReviewRuntimeAdapter.swift` e `FindingIdentityService.swift` ancora nei prefissi engine review hard-fail.
  3. Verificare che i test consumino questi file come bridge verso `ReviewCoreBridge` o orchestratori del runtime Rust.
- Risultato attuale:
  - i cinque file sono ora sotto `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/`
  - il prefisso hard-fail review conserva solo logica engine/domain ancora realmente da migrare
- Risultato atteso: gli adapter review-core Rust devono vivere nel layer infrastrutturale, non nei prefissi dominio `CodeReview` o `VerifiedFindingsCore`.
- Causa probabile: tranche precedenti avevano concentrato il lavoro sul cutover funzionale ma avevano lasciato gli adapter nello stesso subtree storico del dominio review.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/*`
  - `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator+CandidateVerification.swift`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/FindingIdentityService.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/**`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - logica di business residua in `CodeReview`
  - logica di business residua in `VerifiedFindingsCore`
  - nuove FFI o nuove mutazioni del review core Rust
- Moduli confinanti da verificare:
  - `ReviewPipelineCoordinatorTests`
  - `FindingIdentityServiceTests`
  - `ReviewCandidateVerificationServiceTests`
- Test da aggiungere o aggiornare:
  - nessun test nuovo; usare le regression suite gia' esistenti che coprono questi adapter
- Strategia di fix minimo:
  - spostare i cinque file adapter nel layer `Infrastructure/ReviewCore`
  - aggiornare solo i path di progetto Xcode, senza cambiare contratti pubblici o logica
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/FindingIdentityServiceTests -only-testing:CoderEngineTests/ReviewCandidateVerificationServiceTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
  - audit strict review-scope
- Commit previsto: `fix(review): move review core adapters into infrastructure`

## Effetto osservato
- review strict prima del batch: `42` legacy non-UI
- review strict dopo il batch: `37` legacy non-UI
- riduzione per prefisso:
  - `Engine/CoderEngine/Sources/CodeReview`: da `28` a `24`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore`: da `14` a `13`
