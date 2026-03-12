# 2026-03-12 - Tranche 3 runtime Swift facade: alias routing canonico verso MCP Rust

## Modifiche
- esteso `MCPNativeToolRegistry` con una mappa alias `coderide_* -> nome canonico`, senza duplicare le entry pubbliche del catalogo.
- aggiunto il file `UnifiedToolRuntime+MCPCanonicalAliasRouting.swift` con il set esplicito dei tool canonici che devono preferire il path Rust quando il registry e' caldo.
- aggiornato il dispatch del runtime per preferire `executeNativeMCPTool(...)` sui tool canonici quando esiste un alias route nativo.
- spezzati i file grandi toccati:
  - `ToolSchemaCatalog.swift` ora delega gli export in `ToolSchemaCatalog+Exports.swift`
  - `UnifiedToolRuntime+RunDispatch.swift` ora delega il core switch in `UnifiedToolRuntime+RunCoreDispatch.swift`
- aggiunti test:
  - alias registry `coderide_read -> read`
  - preferenza runtime MCP per il tool canonico `read`
- aggiornato `Solo Code.xcodeproj/project.pbxproj` per includere i nuovi file Swift nel target `CoderEngine`.

## Validazione eseguita
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolSchemaCatalogTests -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests`

## Note
- il build Swift e la compilazione dei test passano; l'esecuzione della bundle `CoderEngineTests.xctest` fallisce pero' in questo ambiente per `library load denied by system policy`, quindi il run non e' concluso end-to-end.
- `xcodebuildmcp` non e' disponibile nell'ambiente corrente, quindi la validazione Apple-side e' stata eseguita via `xcodebuild` shell come fallback tecnico.

## Esito
- il facade Swift comincia a delegare davvero il routing dei tool canonici al server Rust quando disponibile
- il catalogo pubblico resta stabile, ma il path operativo si avvicina al cutover Rust unico
