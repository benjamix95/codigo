# 2026-03-29 — Performance audit session schema

## Modifiche
- Esportati nel `ToolSchemaCatalog` i 5 tool performance mancanti, cosi' entrano nei function tool della sessione corrente insieme agli audit security e bug gia' presenti.
  - [ToolSchemaCatalog+AuditTools.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/Entries/Core/ToolSchemaCatalog+AuditTools.swift)
- Allineata la descrizione di `audit_run_profile` ai profili performance realmente supportati dal core audit (`performance_deep`, `performance_extended`, `performance_full`).
  - [ToolSchemaCatalog+AuditTools.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Tools/Catalog/Entries/Core/ToolSchemaCatalog+AuditTools.swift)
- Aggiornate le regressioni del catalogo per impedire che i perf audit spariscano di nuovo dallo schema esportato.
  - [ToolSchemaCatalogTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ToolSchemaCatalogTests.swift)
- Registrato bug record dedicato con perimetro, causa probabile e verifica.
  - [P1-2026-03-29-performance-audit-tools-missing-from-session-schema.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-29-performance-audit-tools-missing-from-session-schema.md)

## Risultato
- Le sessioni che derivano i tool dal `ToolSchemaCatalog` ora vedono anche i perf audit.
- `audit_run_profile` descrive correttamente i profili performance disponibili, riducendo drift tra schema e runtime.

## Verifica
- Target test previsto:
  - `swift test --package-path CoderEngine --filter ToolSchemaCatalogTests`
