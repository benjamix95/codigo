# 2026-03-29 — Canonical MCP enforcement and reporting

## Modifiche
- Rafforzata la policy prompt MCP-first per i tool workspace canonici: quando il live schema espone `coderide_*`, il modello viene istruito a preferire quei nomi invece degli alias runtime generici.
  - [PromptToolsPolicy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/SystemPrompts/Policies/PromptToolsPolicy.swift)
  - [ToolEnabledLLMProvider+Policy.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Policies/ToolEnabledLLMProvider+Policy.swift)
- Il follow-up prompt ora conserva e ripropone il tool MCP effettivamente risolto (`mcp_tool`) e il server, cosi' i round successivi e il riepilogo finale non possono piu' "dimenticare" che il runtime ha usato MCP.
  - [ToolEnabledLLMProvider+SummariesAndParsing.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Helpers/ToolEnabledLLMProvider+SummariesAndParsing.swift)
- I provider con function-calling non esportano piu' insieme il tool runtime generico e l'alias `coderide_*` quando il registry MCP nativo espone gia' la variante canonica. Restano esclusi da questa sostituzione i pochi tool IDE-state che devono rimanere runtime-locali.
  - [ToolSchemaCatalog+Exports.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/ToolSchemaCatalog+Exports.swift)
- Estratta la sezione prompt che elenca i tool MCP nativi in un file dedicato, cosi' la policy principale torna sotto la soglia di 300 righe.
  - [ToolEnabledLLMProvider+MCPPromptSection.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Policies/ToolEnabledLLMProvider+MCPPromptSection.swift)
- Aggiunte regressioni su prompt e follow-up MCP.
  - [SystemPromptsTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/SystemPromptsTests.swift)
  - [ToolEnabledLLMProviderPolicyAckTests+Finalization.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ToolEnabledLLMProviderPolicyAck/ToolEnabledLLMProviderPolicyAckTests+Finalization.swift)
  - [ToolSchemaCatalogTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ToolSchemaCatalogTests.swift)
- Registrato bug record dedicato.
  - [P1-2026-03-29-codex-canonical-mcp-enforcement-and-reporting-gap.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-29-codex-canonical-mcp-enforcement-and-reporting-gap.md)

## Risultato
- Il prompt di sistema e il tool protocol ora spingono in modo esplicito verso i tool `coderide_*`.
- I risultati tool multi-round riportano il tool MCP effettivo (`resolved_mcp_tool`) invece di lasciare solo il nome runtime generico.
- I provider con function schema non presentano piu' doppioni `read` + `coderide_read` nella stessa sessione live quando la variante MCP canonica esiste.
- La probabilita' che Codex concluda "nessun MCP usato" dopo un giro passato via alias canonico si riduce in modo sostanziale.

## Verifica
- Target test previsti:
  - `CoderEngineTests/SystemPromptsTests`
  - `CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests`
  - `CoderEngineTests/ToolSchemaCatalogTests`
