# Changelog — 2026-03-29 — Codex Interleaving Test Hardening

## Problema
I test esistenti sullo streaming interleaved Codex passavano anche quando Codex regrediva a risposte monolitiche (blocco unico di testo senza tool MCP). Questo perché:
1. I test del parser (CoderEngineTests) e i test del reducer (SoloCodeAppTests) erano testati separatamente
2. Nessun test verificava il mapping end-to-end: StreamEvent → ChatPipelineEvent → ChatTurnState
3. Nessun test del bridge `RawArtifactEventAdapter` verificava che i tool types critici producessero `toolTraceArtifact`
4. Nessun test immutabile impediva la modifica dei test per farli passare

## File Creati

### Tests/SoloCodeAppTests/CodexEndToEndInterleavingContractTests.swift
- 7 test end-to-end che verificano il mapping StreamEvent → ChatPipelineEvent → reducer → timeline interleaved
- Simula sequenze realistiche Codex (MCP tools, nativi, mix)
- Verifica logica `isToolRawEvent` per bridge mapping
- ~300 righe

### Tests/SoloCodeAppTests/CodexToolTraceBridgeContractTests.swift
- 22 test del bridge `RawArtifactEventAdapter`
- Verifica che tutti i tool types critici (read, grep, semantic_search, function_call, mcp_tool_call, ecc.) producano `.toolTraceArtifact`
- Verifica tipi artifact (commands, files, mermaid, turn_started)
- Verifica risoluzione titolo tool (mcp_tool > tool > rawType)
- Guardia: tipi sconosciuti restituiscono vuoto
- ~240 righe

### Tests/SoloCodeAppTests/CodexImmutableInterleavingGuardTests.swift
- 10 test IMMUTABILI (marcati "IMMUTABLE GUARD — DO NOT MODIFY THIS TEST")
- Proteggono invarianti fondamentali del sistema di interleaving
- Se falliscono → il bug è nel codice, MAI nel test
- Coprono: text split, N tool = N toolUse, monolitico = 0 toolUse, textReplace preserva tool, tool consecutivi, sequence crescenti
- ~260 righe

### Tests/CoderEngineTests/CodexCLI/CodexCLINativeToolInterleavingRegressionTests.swift
- 7 test di regressione per tool nativi (senza prefix coderide_)
- Verifica che il parser Codex produca raw events per functions.read, functions.grep, functions.bash
- Confronto MCP vs nativo: entrambi devono avere tool_call_id
- ~280 righe

## Scoperta Importante
Durante l'analisi, ho scoperto che `RawArtifactEventAdapter` è già stato aggiornato per gestire i tool types critici (read, grep, semantic_search, ecc.) producendo `.toolTraceArtifact`. I test documentano e proteggono questo comportamento.

## Verifica
- ✅ Build for testing riuscita
- ✅ Tutti i 46 nuovi test passano
- ✅ Tutti i test esistenti (CodexStreamingInterleavedContractTests, CodexMonolithicRegressionGuardTests, CodexMCPToolUseTimelineTests, CodexCLIProviderRealisticSequenceTests) passano senza regressioni
