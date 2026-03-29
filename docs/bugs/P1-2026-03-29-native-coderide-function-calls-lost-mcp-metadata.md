# P1 — I function call nativi `coderide_*` perdevano i marker MCP nel reporting

## Bug Fix Record
- Categoria: B
- Bug: i tool MCP workspace esposti come function call dirette `functions.coderide_*` venivano mappati al tipo runtime corretto (`semantic_search`, `read`, `grep`, ecc.) ma senza conservare `is_mcp`, `mcp_tool` e il server risolto.
- Sintomo: `semantic_search` e altri tool MCP apparivano in chat/timeline come tool normali invece che come tool MCP canonici; questo faceva sembrare che i tool MCP non fossero stati usati davvero.
- Impatto: reporting fuorviante, enforcement MCP-first meno verificabile, perdita di tracciabilita' per audit e debug dei tool workspace.
- Gravita': P1
- Steps to reproduce:
  1. Eseguire un function call nativo come `functions.coderide_semantic_search`.
  2. Osservare che il parser produce `type=semantic_search`.
  3. Verificare che il payload non riporti `is_mcp=true` ne' `mcp_tool=coderide_semantic_search`.
- Risultato attuale: il tool funziona ma il metadata MCP si perde lungo il mapping.
- Risultato atteso: i function call nativi `coderide_*` devono restare eventi del tipo funzionale corretto e conservare sempre i marker MCP.
- Causa probabile: il mapper instradava i tool `coderide_*` verso le route semantiche/read/search prima del branch `mcp_tool_call`, senza una post-elaborazione che reiniettasse i marker MCP nativi.
- Scope consentito:
  - `ProviderToolEventMapper`
  - `CodexCLIProvider` raw event mapping
  - test runtime/parser/UI normalizer correlati
- Non-scope:
  - modifiche al dispatch interno dei tool MCP
  - refactor di `SemanticIndex`
  - refactor ampio delle viste chat
- Moduli confinanti da verificare:
  - `UnifiedToolRuntime` alias routing
  - parser Codex CLI `function_call`
  - `EventNormalizer` app-side
- Test da aggiungere o aggiornare:
  - regressione mapper per `functions.coderide_semantic_search`
  - regressione mapper per un secondo tool workspace (`functions.coderide_read`)
  - regressione parser Codex CLI per `functions.coderide_semantic_search`
  - regressione runtime MCP consistency per alias `semantic_search`
  - regressione `EventNormalizer` che preservi `is_mcp` / `mcp_tool`
- Strategia di fix minimo:
  - aggiungere un post-processing comune nel mapper che riconosca i native tool `coderide_*`
  - conservare `is_mcp`, `mcp_tool`, `mcp_server/server_id`
  - blindare il comportamento con test mirati
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ProviderToolEventMapperTests/testNamespacedCoderideSemanticSearchPreservesMCPMetadata -only-testing:CoderEngineTests/ProviderToolEventMapperTests/testNamespacedCoderideReadPreservesMCPMetadata -only-testing:CoderEngineTests/CodexCLIProviderStreamParsingTests/testFunctionCallNamespacedCoderideSemanticSearchPreservesMCPMetadata -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests/testCanonicalToolFamiliesPreferCoderideAliasesWhenRegistryIsWarm`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/EventNormalizerLiveStateTests/testReadBatchCompletedNamespacedCoderideSemanticSearchPreservesMCPMarkers`
- Commit previsto: `fix(mcp): preserve native coderide tool metadata in event mapping`
