# Changelog — 2026-03-25 — Fix PlanTools test Rust dylib path

## Problema
Tutti i 18 test che richiedono Rust FFI in `CoderIDEMCPServerPlanToolsTests` fallivano con `library_missing` perché la funzione `reviewCoreLibraryPathForCodeReviewTests(from:)` calcolava la repo root salendo 4 livelli di directory — corretto solo per file nella sottodirectory `CodeReview/`, non per file direttamente in `Tests/CoderEngineTests/`.

## Fix
Sostituito il calcolo hardcoded con un walk-up dinamico che cerca la directory `Native/` risalendo l'albero. Fallback al vecchio comportamento (4 livelli) se il marker non viene trovato.

## File modificati
- `Tests/CoderEngineTests/CodeReview/ReviewCoreTestSupport.swift` — nuova funzione `resolveRepoRoot(from:)` con ricerca dinamica

## Risultato
- Prima: 2 passed, 18 failed
- Dopo: 20 passed, 0 failed
- Test pre-esistenti in `CodeReview/` non impattati (verificato `ReviewSessionRegistryTests`)
