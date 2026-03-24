# P0 — PlanTools tests fail: Rust dylib path resolved one level too high

## Bug Fix Record
- **Categoria:** A — Critico (20 test su 20 fallivano a runtime)
- **Bug:** `reviewCoreLibraryPathForCodeReviewTests(from:)` calcola la repo root salendo 4 livelli dal file sorgente. Per file in `Tests/CoderEngineTests/CodeReview/` (4 livelli) funziona, ma `CoderIDEMCPServerPlanToolsTests.swift` è direttamente in `Tests/CoderEngineTests/` (3 livelli). Il path risultante puntava a `/Users/.../Native/target/debug/...` invece che alla repo root.
- **Sintomo:** `[RustFFI] Rust dylib: FAILED — reason=library_missing, tried 14 paths` su ogni test che invoca Rust FFI.
- **Impatto:** 18 test su 20 fallivano (i 2 che passavano sono test di validazione pura Swift che non invocano Rust).
- **Gravità:** P0 — tutti i test PlanTools erano non funzionanti.
- **Steps to reproduce:** `xcodebuild test -scheme CoderEngineTests-Debug -only-testing:CoderEngineTests/CoderIDEMCPServerPlanToolsTests -destination 'platform=macOS'`
- **Risultato attuale:** 18 failure con `library_missing`
- **Risultato atteso:** 20/20 pass
- **Causa probabile:** Hardcoded 4x `deletingLastPathComponent()` non funziona per file a profondità diversa.
- **Scope consentito:** `Tests/CoderEngineTests/CodeReview/ReviewCoreTestSupport.swift`
- **Non-scope:** Nessun file di produzione toccato.
- **Moduli confinanti da verificare:** Tutti i test in `CodeReview/` che usano la stessa funzione.
- **Test da aggiungere o aggiornare:** Nessuno (i test esistenti ora funzionano).
- **Strategia di fix minimo:** Sostituire il calcolo hardcoded con walk-up dinamico che cerca la directory `Native/`.
- **Verifica post-fix:** 20/20 test passano. Test `ReviewSessionRegistryTests` (CodeReview/) verificato: passa ancora.
- **Commit previsto:** `fix(tests): resolve Rust dylib path dynamically in reviewCoreLibraryPathForCodeReviewTests`
