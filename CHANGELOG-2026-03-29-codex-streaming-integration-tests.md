# Changelog — 2026-03-29 — Codex Streaming Integration Tests

## Obiettivo
Colmare il gap critico nei test dello streaming chat interleaved Codex, dove i test
passavano anche quando Codex regrediva a output monolitico senza usare tool MCP.

## Problema
I test esistenti operavano a due livelli isolati:
1. **Provider level** (CodexCLIProviderStreamParsingTests) — testano parsing di singoli eventi
2. **Reducer level** (CodexMonolithicRegressionGuardTests) — testano con eventi sintetici pre-costruiti

Nessun test verificava la **catena completa**: `StreamEvent.raw` → `RawArtifactEventAdapter` → `ChatPipelineReducer` → `ChatTurnState.timelineSegments`.

Se Codex smetteva di emettere `function_call` per tool MCP e mandava tutto come testo monolitico,
entrambi i livelli di test continuavano a passare.

## File creati

### Tests/SoloCodeAppTests/CodexProviderToReducerIntegrationTests.swift
- **6 test** di integrazione che verificano la catena completa provider→adapter→reducer
- `testRealisticCodexMCPSequenceProducesInterleavedTimeline` — sequenza realistica con 2 tool MCP
- `testMonolithicCodexOutputHasNoToolSegments` — output monolitico rilevato correttamente
- `testCodexNativeFunctionCallProducesToolTraceArtifact` — tool nativi producono toolTrace
- `testRawArtifactEventAdapterMappingContract` — contratto di mapping per ogni rawType
- `testMixedRawTypesProduceCorrectTimelinePattern` — mix MCP + nativi + file_change
- `testTextReplaceAfterToolsPreservesToolUseSegments` — textReplace non distrugge tool

### Tests/SoloCodeAppTests/CodexStreamingRegressionImmutabilityTests.swift
- **8 test** di invarianti strutturali del reducer
- `testReducerToolTraceAlwaysCreatesDistinctToolSegment` — invariante fondamentale
- `testTimelineSegmentCountInvariantForKnownSequence` — conteggio esatto 3T+4text=7
- `testTextSegmentsAreNeverMergedAcrossToolBoundaries` — no fusione testi
- `testToolTraceWithEmptyDetailStillInsertsToolUseSegment` — tool senza detail
- `testConsecutiveToolTracesEachProduceDistinctSegment` — tool consecutivi
- `testBlocksReflectTimelineSegmentsExactly` — blocks coerenti con segments
- `testTextReplaceDoesNotDestroyExistingToolUseSegments` — textReplace safe
- `testMonolithicRegressionDetectionHelperIsSound` — helper detection per N=1..5

## File rimossi
- `Tests/SoloCodeAppTests/CodexEndToEndInterleavingContractTests.swift` — creato da subagent con errori di compilazione (access level), rimosso.

## Verifica
Tutti i 14 test passano con 0 failures su macOS.
