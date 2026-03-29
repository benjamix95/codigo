# Changelog - 2026-03-29 - search provider enforcement and UI

## Cosa ho cambiato
- aggiunto enforcement provider-wide che forza `semantic_search` per query umane quando un provider cloud prova a usare `grep`, `search` o `mcp_call -> coderide_grep`
- aggiornato il mapper eventi per trattare `search` naturale come `semantic_search` invece che come ricerca generica
- aggiunte regression UI per far apparire `coderide_semantic_search` come `Semantic Search` nella timeline e nei task activity

## Effetto pratico
- il semantic search diventa obbligatorio per tutti i provider su query umane di code discovery
- la UI mostra in modo esplicito `Semantic Search` anche sul path MCP/cloud, non solo sul path locale diretto

## Verifiche
- `CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests`
- `CoderEngineTests/ProviderToolEventMapperTests`
- `SoloCodeAppTests/ChatTurnInlineToolGroupRowPresentationTests`
- `SoloCodeAppTests/EventNormalizerLiveStateTests`
