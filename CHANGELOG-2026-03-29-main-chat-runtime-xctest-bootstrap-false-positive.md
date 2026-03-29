# 2026-03-29 - Main chat runtime false positive XCTest bootstrap

## Modifiche
- corretta [RustSearchFFIClient.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift): `shouldDeferRustReviewCoreBootstrap(...)` non usa più euristiche globali su bundle/framework/classi XCTest e si basa solo su marker espliciti dell'environment
- corretta [build_rust_search_backend.sh](/Users/benjaminstoica/SoloCode/scripts/build_rust_search_backend.sh): se l'artifact Rust è già aggiornato, lo script ricopia comunque la dylib cached negli output richiesti (`BUILT_PRODUCTS_DIR`, bundle app) prima dello skip
- aggiunta regressione in [ReviewCoreBootstrapPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/ReviewCoreBootstrapPolicyTests.swift) per garantire che un launch app normale non deferisca il runtime Rust
- aggiunta regressione app-side in [ChatStoreRustBootstrapPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests.swift) per garantire che lo store non salti il bootstrap Rust con environment normale
- documentato il bug in [P1-2026-03-29-main-chat-runtime-disabled-by-false-xctest-bootstrap-signals.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-29-main-chat-runtime-disabled-by-false-xctest-bootstrap-signals.md)
- documentato il bug di packaging cached in [P2-2026-03-29-rust-build-cache-skip-did-not-refresh-app-bundle.md](/Users/benjaminstoica/SoloCode/docs/bugs/P2-2026-03-29-rust-build-cache-skip-did-not-refresh-app-bundle.md)

## Impatto
- la risoluzione del provider runtime della main chat non viene più disattivata da falsi positivi XCTest
- il fail-closed rimane attivo solo nei casi voluti: host XCTest esplicito o flag Rust disabilitati
