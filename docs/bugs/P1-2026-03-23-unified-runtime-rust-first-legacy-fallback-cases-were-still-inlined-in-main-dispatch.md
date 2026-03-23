## Bug Fix Record
- Categoria: A - Critico
- Bug: `UnifiedToolRuntime` manteneva ancora inlined nel `main dispatch` i case legacy dei tool gia' classificati come Rust-first, anche se sul path standard quei branch dovevano ormai vivere solo come fallback locale esplicito.
- Sintomo:
  - il `switch` principale continuava a contenere implementazioni Swift locali per `read`, `grep`, `glob`, `write`, `debug_*`, `audit_*`, `web_*`, `skill`, `subagent_*` e altri tool gia' nel perimetro Rust-first;
  - il confine tra path standard Rust-owned e fallback locale restava implicito nella struttura del file, non solo nel comportamento runtime.
- Impatto: ownership architetturale meno difendibile, con rischio di regressioni future in cui nuovi case Rust-first venivano reintrodotti nel `main dispatch` invece di restare confinati in un fallback legacy esplicito.
- Gravita': P1
- Steps to reproduce:
  1. Aprire `UnifiedToolRuntime+RunCoreDispatch.swift`.
  2. Osservare che il `switch` principale conteneva ancora numerosi case di tool gia' classificati come Rust-first.
  3. Notare che il fallback locale era corretto a runtime solo grazie a gate sparsi, ma non risultava drenato strutturalmente dal dispatch canonico.
- Risultato attuale:
  - il behavior Rust-first era gia' in gran parte corretto;
  - la struttura del dispatch lasciava pero' in `main` i branch locali legacy;
  - i test di coerenza locale non esplicitavano ancora sempre il contesto `enableMCP=false`.
- Risultato atteso:
  - il `main dispatch` deve restare focalizzato sui branch Swift-owned e sui path MCP canonici;
  - i fallback locali dei tool Rust-first devono vivere in un helper legacy esplicito, attivato solo con MCP disabilitato o registry ancora freddo;
  - i test che validano il fallback locale devono dichiarare quel contesto in modo esplicito.
- Causa probabile:
  - il cutover Rust-first precedente aveva corretto il comportamento osservabile, ma non aveva ancora drenato la struttura del dispatch centrale;
  - alcune regressioni testavano il fallback locale senza isolare chiaramente la policy `enableMCP=false`.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Core/Execution/Dispatch/UnifiedToolRuntime+RunCoreDispatch.swift`
  - `Tests/CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests.swift`
- Non-scope:
  - nuovi tool MCP
  - merge dei binari Rust
  - refactor dei pannelli app-side
  - modifica delle suite MCP note per hang preesistenti su `listServers`
- Moduli confinanti da verificare:
  - `UnifiedToolRuntime+MCPCanonicalAliasRouting`
  - `UnifiedToolRuntimeMCPConsistencyTests`
  - test runtime locali su `write`, `grep`, `glob`, `find_symbol`, `debug_context`, `read_lints`
- Test da aggiungere o aggiornare:
  - esplicitare il contesto locale con `enableMCP=false` per i test che convalidano il fallback legacy;
  - rilanciare la suite di coerenza MCP e un sottoinsieme mirato di `UnifiedToolRuntimeTests` sui path drenati.
- Strategia di fix minimo:
  - spostare i case Rust-first legacy dal `switch` principale in un helper dedicato;
  - lasciare quel fallback disponibile solo per contesto locale esplicito o registry MCP ancora freddo;
  - aggiornare i test per distinguere chiaramente path standard Rust-first e fallback locale.
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testWriteCreatesAndOverwrites -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testEventTypeForStrReplace -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testEventTypeForCreateFile -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testGrepAcceptsPatternAlias -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testGlobPathScopeAliasProducesCountAndPreview -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testFindSymbolKeepsKindAndFuzzyContractWhenLanguageServiceIsPresent -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testDebugContextRoutesCorrectly -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testReadLintsRoutesViaReadLintsTool`
- Commit previsto:
  - `refactor(runtime): isolate legacy fallback for rust-first tool cases`

## Stato
- corretto il 2026-03-23
