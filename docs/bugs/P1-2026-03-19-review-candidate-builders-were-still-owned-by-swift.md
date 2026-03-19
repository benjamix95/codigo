# P1 - I builder dei review candidate erano ancora owned da Swift

## Bug Fix Record
- Categoria: A
- Bug: dopo il porting di sessione, provider parsing e fix-stage planner, la costruzione dei `ReviewCandidate` da finding e da review task restava ancora logica Swift locale.
- Sintomo:
  - `ReviewCandidateVerificationService.candidate(from:signalType:)`
  - `ReviewPipelineCoordinator.reviewCandidate(from:prefix:)`
  continuavano a derivare campi canonici (`severity`, `category`, `signalType`, fallback `expectedInvariant/reproOrReasoning`) fuori dal core Rust.
- Impatto: il runtime review manteneva ancora due source of truth sulla semantica dei candidate, con rischio di drift fra provider/task extraction e session/runtime.
- Gravita': alta, perche' tocca i candidati che entrano nella verification e poi nella promozione a finding.
- Steps to reproduce:
  1. Ispezionare i due builder Swift nel pipeline review.
  2. Verificare che severity/category e fallback da `verificationReport`/`suggestedFix` siano derivati localmente.
  3. Notare che il core Rust non vedeva `verificationReport` nel payload FFI del finding.
- Risultato attuale: candidate creation non ancora canonica in Rust.
- Risultato atteso: i candidate review devono essere costruiti dal core Rust; Swift deve solo invocare il bridge e fallire chiuso se il core non risponde.
- Causa probabile: i path di candidate building erano rimasti nel coordinator/runtime adapter per comodita' delle tranche iniziali.
- Scope consentito:
  - `Native/RustCore/src/review_pipeline/*`
  - `Native/RustCore/src/ffi/*`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+CandidateVerification.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewRuntimeAdapter.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Pipeline/ReviewPipelineCoordinator+Rounds.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Session/CodeReviewFinding.swift`
  - `Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - execution host dei worker
  - audit execution engine
  - panel runtime
  - patch workflow completo
- Moduli confinanti da verificare:
  - `ReviewPipelineCoordinatorTests`
  - `CodeReviewMultiSwarmProviderTests`
  - `ReviewRuntimeAdapter`
  - `ReviewPipelineCoordinator+Rounds`
- Test da aggiungere o aggiornare:
  - regression Rust per candidate da finding
  - regression Rust per candidate da task
  - regression XCTest sui due builder e sulle suite provider/pipeline confinanti
- Strategia di fix minimo:
  - introdurre boundary Rust per `review_core_candidate_from_finding`
  - introdurre boundary Rust per `review_core_candidate_from_review_task`
  - rendere fail-closed i callsite runtime (`ReviewRuntimeAdapter`, `ReviewPipelineCoordinator+Rounds`) se il builder Rust non risponde
  - completare il payload `Codable` di `CodeReviewFinding` con i campi necessari al bridge
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_pipeline::candidates::tests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
- Commit previsto: `refactor(review-candidates): route candidate builders through rust`

## Effetto osservato
- I review candidate del runtime sono ora costruiti dal core Rust.
- I callsite runtime falliscono chiusi se il builder Rust non e' disponibile.
- Il payload FFI del finding non perde piu' `verificationReport` e gli altri campi review-specifici necessari.
