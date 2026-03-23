# P1 - Il comando `review_configure` continuava a normalizzare e applicare la config in Swift

## Bug Fix Record
- Categoria: A
- Bug: il command loop review calcolava ancora in Swift la config aggiornata per `configure` e la applicava localmente sia alle sessioni live (`ReviewSessionRegistry`) sia agli snapshot persistiti.
- Sintomo: `dismiss`, `comment` e `apply_fix` passavano dal boundary Rust, mentre `configure` seguiva un path separato Swift-owned con semantica propria.
- Impatto: rischio di drift su clamp dei valori, payload command-side, evento `config_updated` e comportamento differente tra sessione live e snapshot offline.
- Gravita': alta, perche' tocca lifecycle condiviso e configurazione del runtime review.
- Steps to reproduce:
  1. Enqueue di un comando `configure` con `max_workers`, `max_rounds` o `analysis_only`.
  2. Esecuzione sul command loop review.
  3. Osservazione del path `SoloCodeApp+CodeReviewCommands.swift` e `ReviewSessionRegistry.swift`.
- Risultato attuale: la config veniva costruita e scritta in Swift con evento sintetico locale.
- Risultato atteso: la config deve essere normalizzata e applicata dal mutator Rust anche per `configure`, con Swift ridotto a persistence e reidratazione snapshot.
- Causa probabile: la tranche precedente aveva migrato le mutazioni review piu' frequenti ma non il path di configurazione.
- Scope consentito:
  - `Native/RustCore/src/review_command/*`
  - `Engine/CoderEngine/Sources/CodeReview/Session/*`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/*`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/SoloCodeApp+CodeReviewCommands.swift`
  - `Tests/CoderEngineTests/CodeReview/ReviewSessionRegistryTests.swift`
  - `Tests/SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests.swift`
  - `docs/bugs`, `docs/changelog`
- Non-scope:
  - pipeline execution review
  - UI SwiftUI del panel
  - migrazione completa del runtime provider in Rust
- Moduli confinanti da verificare:
  - `review_command::planner`
  - `review_command::mutator`
  - `ReviewSessionRegistry`
  - command loop review dell'app
- Test da aggiungere o aggiornare:
  - unit Rust per `configure` nel mutator
  - regressione engine sul registry live
  - regressione app-side sul configure offline persistito
- Strategia di fix minimo:
  - estendere `review_core_command_mutate_snapshot` a restituire config normalizzata per `configure`
  - instradare `ReviewSessionRegistry.updateConfig` attraverso il boundary Rust
  - riusare lo stesso boundary Rust anche per il path snapshot-only del command loop
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet`
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --quiet`
  - validazione `xcodebuildmcp` ancora non eseguibile in questa sessione per mancanza tool
- Commit previsto: `refactor(review-command): route configure through rust mutation`
