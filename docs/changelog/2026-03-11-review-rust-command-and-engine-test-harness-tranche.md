# 2026-03-11 - Review Rust command + engine test harness tranche

## Modifiche
- estesa la mutazione Rust `review_command::mutator` per coprire anche `close_finding`, mantenendo in Swift solo il wiring del command loop
- aggiornato `CodigoApp+CodeReviewCommandMutations.swift` per usare il fast path Rust anche su `close_finding`
- aggiunto il test `close_finding_requires_validated_apply_or_terminal_status` nel core Rust
- aggiunto `CodigoAppCodeReviewCommandLoopCloseFindingTests.swift` per coprire il path command loop app-side della chiusura finding da snapshot persistito
- introdotto `scripts/bootstrap_test_bundles.sh` per rimuovere `com.apple.provenance` / `quarantine` e rifirmare i bundle test
- aggiornato `scripts/generate_xcode_project.rb` per:
  - embed di `CoderEngine.framework` e `CoderIDEMCPServer.framework` nel bundle `CoderEngineTests.xctest`
  - pre-action di bootstrap sugli scheme test
  - nuovo scheme dedicato `CoderEngineTests-Debug` per validazione isolata del target engine
- aggiornato `scripts/solocode-validate` per usare `build-for-testing` + bootstrap bundle + `test-without-building`
- aggiunte regressioni strutturali in `AppBundleProjectStructureTests.swift`

## Verifica
- verde: `cargo test -q close_finding_requires_validated_apply_or_terminal_status`
- verde: `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewFindingTests`
- verificato: il bundle `CoderEngineTests.xctest` viene costruito con framework embed e la sessione test parte nello scheme dedicato

## Note
- la validazione `Solo Code-Debug` completa resta bloccata da un bug preesistente del target app: `SidebarView` mancante in `ContentView+Layout+Composition.swift`
- un test persistence Postgres mirato fallisce ancora su data directory locale sporca, non per regressione di questa tranche
