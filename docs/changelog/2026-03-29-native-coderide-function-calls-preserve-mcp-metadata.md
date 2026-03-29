# 2026-03-29 — Native `coderide_*` function calls preserve MCP metadata

## Modifiche
- Aggiunto un helper dedicato che riconosce i native tool `coderide_*` e reinietta nel payload `is_mcp`, `mcp_tool`, `mcp_server` e `server_id` anche quando il tool viene renderizzato come evento funzionale (`semantic_search`, `read`, ecc.).
  - [ProviderToolEventMapper+MCPMetadata.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+MCPMetadata.swift)
- Il routing centrale del mapper ora applica sempre questa annotazione post-mapping, cosi' la correzione vale per tutti i tool workspace canonici e non solo per `semantic_search`.
  - [ProviderToolEventMapper+Routes.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Routes.swift)
- Aggiunte regressioni su mapper, parser Codex CLI, alias runtime MCP e normalizzazione app-side.
  - [ProviderToolEventMapperTests+Core.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ProviderToolEventMapper/ProviderToolEventMapperTests+Core.swift)
  - [CodexCLIProviderStreamParsingTests+StreamMappingsTool.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodexCLI/CodexCLIProviderStreamParsingTests+StreamMappingsTool.swift)
  - [UnifiedToolRuntimeMCPConsistencyTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests.swift)
  - [EventNormalizerLiveStateTests+Commands.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/EventNormalizer/EventNormalizerLiveStateTests+Commands.swift)
- Registrato il bug record dedicato.
  - [P1-2026-03-29-native-coderide-function-calls-lost-mcp-metadata.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-29-native-coderide-function-calls-lost-mcp-metadata.md)

## Risultato
- `semantic_search` nativo via `functions.coderide_semantic_search` resta visibile come ricerca semantica ma non perde piu' l'identita' MCP.
- Lo stesso comportamento vale anche per gli altri tool workspace `coderide_*`, perche' il fix e' centralizzato nel mapper condiviso.
- I layer di parser, runtime e app normalizer hanno ora regressioni esplicite che impediscono di reintrodurre il problema in silenzio.

## Verifica
- Test engine mirati eseguiti con successo:
  - `ProviderToolEventMapperTests/testNamespacedCoderideSemanticSearchPreservesMCPMetadata`
  - `ProviderToolEventMapperTests/testNamespacedCoderideReadPreservesMCPMetadata`
  - `CodexCLIProviderStreamParsingTests/testFunctionCallNamespacedCoderideSemanticSearchPreservesMCPMetadata`
  - `UnifiedToolRuntimeMCPConsistencyTests/testCanonicalToolFamiliesPreferCoderideAliasesWhenRegistryIsWarm`
- Test app-side mirato eseguito con successo:
  - `EventNormalizerLiveStateTests/testReadBatchCompletedNamespacedCoderideSemanticSearchPreservesMCPMarkers`
