# 2026-03-23 — Hardening loader/bundle del review core Rust

## Modifiche
- aggiornato [RustSearchFFIClient.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift) per non scandire più i `DerivedData` globali quando il processo gira già dentro un bundle `.app`
- aggiornato [build_rust_search_backend.sh](/Users/benjaminstoica/SoloCode/scripts/build_rust_search_backend.sh) per:
  - fallire chiuso quando il bundle richiede il review core Rust ma `cargo/rustc` non sono disponibili
  - copiare gli artifact tramite file temporaneo + `mv`, evitando overwrite non atomici del path finale
  - rifirmare ad-hoc ogni `libsolocode_rust_core.dylib` copiata, incluso il path bundle-side
  - usare `/usr/bin/tr` nel preflight del profilo, così il branch fail-closed funziona anche con `PATH` minimale
- estesi i test in [ReviewCoreBootstrapPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/ReviewCoreBootstrapPolicyTests.swift) per coprire:
  - la policy che disabilita il fallback `DerivedData` dentro un `.app`
  - il caso fail-closed senza toolchain
  - lo smoke build/sign della dylib copiata nel bundle
- riallineato [AppBundleRustReviewCoreScriptTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/AppBundle/AppBundleRustReviewCoreScriptTests.swift) per simulare davvero l’assenza della toolchain anche quando esiste `~/.cargo/bin`

## Motivazione
- evitare che un `dlopen` fallito sul bundle corrente venga “mascherato” caricando una dylib da un altro `DerivedData`, con rischio di runtime stale o non coerente con l’app in esecuzione
- rendere più robusto il packaging locale del review core Rust nel bundle macOS

## Verifica
- smoke fail-closed:
  - `PATH=/usr/empty HOME=<fake-home> SRCROOT=/Users/benjaminstoica/SoloCode CONFIGURATION=Debug SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR=<tmp>/Solo Code.app/Contents/MacOS/solocode_rust /bin/bash scripts/build_rust_search_backend.sh`
  - esito osservato: `rc=1` con messaggio `review core Rust richiesto...`
- smoke build/sign bundle:
  - `SRCROOT=/Users/benjaminstoica/SoloCode CONFIGURATION=Debug SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR=<tmp>/SoloCode.app/Contents/MacOS/solocode_rust /bin/bash scripts/build_rust_search_backend.sh`
  - `codesign --verify --verbose=4 <tmp>/SoloCode.app/Contents/MacOS/solocode_rust/libsolocode_rust_core.dylib`
  - esito osservato: `verify_rc=0`
- tentato `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewCoreBootstrapPolicyTests`
  - bloccato da errore preesistente in [UsageFooterContextProgressTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/UsageFooterContextProgressTests.swift): `IndexingProgress` initializer inaccessibile

## Note
- resta aperto, separatamente da questa tranche, il warning runtime `onChange(of: Int) action tried to update multiple times per frame.` emerso nello stesso log iniziale
