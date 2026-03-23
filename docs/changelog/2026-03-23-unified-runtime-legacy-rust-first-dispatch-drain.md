## 2026-03-23 - Unified runtime legacy rust-first dispatch drain

- I case legacy dei tool gia' Rust-first non vivono piu' direttamente nel `main dispatch` di `UnifiedToolRuntime`, ma in un helper dedicato usato solo per fallback locale esplicito.
- Il `switch` principale resta piu' vicino al boundary architetturale reale:
  - path standard MCP / Rust-first
  - branch Swift-owned residui
- I fallback locali dei test runtime sono ora espliciti anche nella suite di coerenza MCP tramite `ToolRuntimePolicy(enableMCP: false)`.

### Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testWriteCreatesAndOverwrites -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testEventTypeForStrReplace -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testEventTypeForCreateFile -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testGrepAcceptsPatternAlias -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testGlobPathScopeAliasProducesCountAndPreview -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testFindSymbolKeepsKindAndFuzzyContractWhenLanguageServiceIsPresent -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testDebugContextRoutesCorrectly -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testReadLintsRoutesViaReadLintsTool`

### Avanzamento
- Avanzamento complessivo del cutover Rust-first: **100%**

### Note
- La suite ampia `UnifiedToolRuntimeTests` continua ad avere un hang preesistente su `testMCPListServersAlwaysCompletes`, quindi la validazione di questa tranche resta volutamente mirata ai path toccati dal refactor finale.
