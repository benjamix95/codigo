# P1 — Parita' incompleta tra catalogo canonico, schema Rust e precedence provider-specifica dei tool

## Bug Fix Record
- Categoria: B
- Bug: mancavano guardrail automatici che verificassero che ogni tool canonico fosse coperto in modo coerente da catalogo Rust, schema/input JSON, riconoscimento workspace UI e export provider; inoltre il fallback prompt Rust di Claude poteva andare in drift rispetto alla policy shared.
- Sintomo: un tool poteva risultare presente nel registry canonico ma sfuggire a schema coverage, export provider o provider prompt fallback; Claude in particolare poteva mantenere istruzioni meno rigide sull'uso dei tool `coderide_*`.
- Impatto: rischio di drift silenzioso tra registry/UI/Rust/provider, precedenza tool non uniforme su tutti gli LLM.
- Gravita': P1
- Steps to reproduce:
  1. Aggiungere o modificare un tool nel registry canonico.
  2. Dimenticare di aggiornarne schema, export o prompt provider-specifico.
  3. Osservare che il problema non emerge finche' il tool non viene usato manualmente.
- Risultato attuale: esistevano test parziali, ma non una copertura esplicita per schema Rust completo, workspace recognition provider-wide e fallback prompt Claude.
- Risultato atteso: qualunque drift tra registry canonico, schema Rust, export provider o fallback prompt deve fallire in test.
- Causa probabile: controlli di contratto presenti ma non completi su tutte le superfici.
- Scope consentito:
  - test di contratto catalogo/tool export
  - fallback prompt Claude Rust
  - documentazione bug/changelog
- Non-scope:
  - refactor del catalogo
  - modifica del dispatcher runtime principale
  - redesign UI
- Moduli confinanti da verificare:
  - `CoderIDECanonicalToolRegistry`
  - `tool_names.txt`
  - `tool_schema.rs`
  - export `ToolSchemaCatalog`
  - fallback prompt `claude.rs`
- Test da aggiungere o aggiornare:
  - copertura schema Rust su tutti i tool canonici
  - riconoscimento workspace catalog per tutti i tool provider-available
  - parita' export provider su tutti i preferred canonical names
  - controllo testuale del fallback prompt Claude
- Strategia di fix minimo:
  - aggiungere test di contratto mirati
  - irrigidire il prompt fallback Claude sui tool `coderide_*`
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:CoderEngineTests/CoderIDErustCatalogContractTests/testEveryRustCatalogToolHasSchemaCoverage -only-testing:CoderEngineTests/CoderIDErustCatalogContractTests/testProviderAvailableCanonicalToolsAreRecognizedAsWorkspaceTools -only-testing:CoderEngineTests/CoderIDErustCatalogContractTests/testRustClaudeFallbackPromptEnforcesCoderideFirstSearchAndRead -only-testing:CoderEngineTests/ToolSchemaCatalogProviderExportTests/testProviderExportsAllPreferredCanonicalNamesWhenNativeRegistryIsWarm`
- Commit previsto: `test(catalog): enforce provider and rust tool parity`
