# 2026-03-29 — Catalog parity and provider tool precedence contracts

## Modifiche
- Rafforzato il fallback prompt Rust di Claude: ora dichiara in modo esplicito che i tool `coderide_*` sono la prima scelta, vieta native search/read/edit equivalenti e vieta shell discovery nel workspace.
  - [claude.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/main_chat/providers/cli/claude.rs)
- Estesi i test di contratto per coprire:
  - schema Rust per tutti i tool canonici;
  - riconoscimento `WorkspaceToolCatalog` per tutti i tool provider-available;
  - export provider (`OpenAI` / `Anthropic`) su tutti i nomi canonici preferiti;
  - contenuto del fallback prompt Claude.
  - [CoderIDErustCatalogContractTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CoderIDErustCatalogContractTests.swift)
  - [ToolSchemaCatalogProviderExportTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/ToolSchemaCatalogProviderExportTests.swift)
- Registrato bug record dedicato.
  - [P1-2026-03-29-catalog-parity-and-provider-tool-precedence-gaps.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-29-catalog-parity-and-provider-tool-precedence-gaps.md)

## Risultato
- Ogni tool canonico provider-available deve ora risultare coerente tra registry, schema Rust, export provider e riconoscimento workspace.
- Il path Claude fallback non puo' piu' degradare la precedence dei tool `coderide_*` senza rompere i test.

## Verifica
- Test mirati eseguiti con successo:
  - `CoderIDErustCatalogContractTests/testEveryRustCatalogToolHasSchemaCoverage`
  - `CoderIDErustCatalogContractTests/testProviderAvailableCanonicalToolsAreRecognizedAsWorkspaceTools`
  - `CoderIDErustCatalogContractTests/testRustClaudeFallbackPromptEnforcesCoderideFirstSearchAndRead`
  - `ToolSchemaCatalogProviderExportTests/testProviderExportsAllPreferredCanonicalNamesWhenNativeRegistryIsWarm`
- Nota ambiente:
  - per questa tranche il run e' stato eseguito con `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` per evitare un problema locale di signing del bundle test non correlato alla logica verificata.
