# P1 — Il build phase Xcode del review core Rust non puo' leggere il crate sotto sandbox

## Bug Fix Record
- Categoria: A
- Bug: il build phase `Build Rust Search Backend` del target `CoderEngine` falliva sotto `xcodebuild` quando tentava di leggere `Native/RustCore/Cargo.toml`.
- Sintomo: `xcodebuild test` poteva interrompersi prima dei test con `Operation not permitted` o `failed to read ... Cargo.toml`.
- Impatto: il backend Rust non si costruiva nel path Xcode e la suite review non poteva validare il percorso nativo in modo affidabile.
- Gravita': alta lato integrazione toolchain, media lato runtime perche' esiste fallback Swift.
- Steps to reproduce:
  1. Installare `cargo`.
  2. Lanciare `xcodebuild test` sul workspace senza forzare skip del build phase Rust.
  3. Osservare il failure del phase script sotto sandbox.
- Risultato attuale: il build phase puo' essere bloccato dal sandbox Xcode anche quando il crate Rust compila correttamente da shell.
- Risultato atteso: il build phase non deve bloccare build/test quando il sandbox impedisce l'accesso al crate; deve degradare in fallback pulito.
- Causa probabile: il sandbox del phase script non concede accesso completo al crate Rust nel repo e agli output custom.
- Scope consentito:
  - `Solo Code.xcodeproj/project.pbxproj`
  - `scripts/benchmark_review_pipeline_pre_post.sh`
- Non-scope:
  - redesign completo dell'integrazione Rust in Xcode
  - linking statico nativo dentro il target Swift
- Moduli confinanti da verificare:
  - `RustSearchFFIClient`
  - script benchmark review-core
  - build/test via `xcodebuild`
- Test da aggiungere o aggiornare:
  - smoke benchmark `pre/post` che prebuilda il crate fuori da Xcode e skippa il phase script nel run benchmark
- Strategia di fix minimo:
  - rendere il build phase non bloccante
  - introdurre `SOLOCODE_RUST_SKIP_XCODE_BUILD=1` per i run benchmark/test controllati
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test ... -only-testing:CoderEngineTests/FindingIdentityServiceTests`
  - `scripts/benchmark_review_pipeline_pre_post.sh --phase pre|post --tag review-core-tranche1`
- Commit previsto: `fix(review): harden rust review-core build fallback under xcode sandbox`
