# P1 - Parsing e diagnostica del provider review erano ancora owned da Swift

## Bug Fix Record
- Categoria: A
- Bug: il boundary review aveva gia' sessione e pipeline Rust, ma parsing prompt/scope, validazione `AGAINST`, task extraction e classificazione re-review restavano ancora semantica Swift locale nel provider multi-swarm.
- Sintomo: `CodeReviewMultiSwarmProvider+Scope.swift`, `...+Parsing.swift` e `...+Diagnostics.swift` continuavano a decidere in Swift:
  - parse di `[REVIEW_SCOPE:...]` e `[AGAINST:...]`
  - validazione e normalizzazione delle revisioni git
  - estrazione task JSON e deduplica file/worker id
  - verdict `issues/clean/inconclusive` del testo di re-review
- Impatto: il provider runtime non era ancora Rust-owned sui path che preparano le decisioni del loop review; persisteva rischio di drift tra orchestratore Rust e helper Swift del provider.
- Gravita': alta, perche' tocca orchestrazione runtime, task planning, retry/re-review loop e confini UI/runtime.
- Steps to reproduce:
  1. Eseguire `CodeReviewMultiSwarmProviderTests`.
  2. Verificare che parsing scope/ref, task extraction e findings classification passino tutti da helper Swift statici.
  3. Osservare che il core Rust non e' l’unica source of truth per queste decisioni.
- Risultato attuale: una parte della semantica provider/pipeline resta ancora fuori da Rust.
- Risultato atteso: parsing prompt/scope/ref, task extraction e reduce del verdict review devono essere serviti dal core Rust e Swift deve limitarsi a bridge/host tecnico.
- Causa probabile: nella tranche iniziale del cutover pipeline il core Rust governava la state machine, ma non gli helper di parsing e diagnostica del provider.
- Scope consentito:
  - `Native/RustCore/src/review_pipeline/*`
  - `Native/RustCore/src/ffi/*`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Core/CodeReviewMultiSwarmProvider.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Core/CodeReviewMultiSwarmProvider+Diagnostics.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Core/Parsing/CodeReviewMultiSwarmProvider+Parsing.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Core/Scope/CodeReviewMultiSwarmProvider+Scope.swift`
  - `Tests/CoderEngineTests/CodeReview/CodeReviewMultiSwarmProviderTests+Parsing.swift`
  - `Tests/CoderEngineTests/CodeReview/ReviewPipelineCoordinatorTests.swift`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - host I/O provider
  - fix worker execution
  - audit execution
  - panel runtime
  - patch workflow
- Moduli confinanti da verificare:
  - `CodeReviewMultiSwarmProviderTests`
  - `ReviewPipelineCoordinatorTests`
  - `ReviewPipelineRustDriver`
  - `ReviewRuntimeAdapter`
- Test da aggiungere o aggiornare:
  - regression Rust su bare-array extraction, duplicate task ids, scope inference e verdict classification
  - setup XCTest condiviso per il dylib del review core sui test provider
- Strategia di fix minimo:
  - introdurre boundary Rust `review_core_provider_plan_step` e `review_core_provider_reduce_event`
  - spostare nel core Rust parse scope/ref, validazione/normalizzazione `AGAINST`, task extraction e verdict classification
  - lasciare in Swift solo wrapper sottili che mappano request/response
  - aggiornare i test provider/pipeline per usare il resolver condiviso del dylib
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files ... --format text`
- Commit previsto: `refactor(review-provider): route parsing helpers through rust`

## Effetto osservato
- Il provider review usa ora il core Rust per scope/ref parsing, task extraction e reduce del verdict.
- Swift non ricostruisce piu' localmente la semantica dei helper provider; se il core Rust non risponde, il path fallisce chiuso.
- Le suite provider e pipeline restano verdi dopo il rebinding.
