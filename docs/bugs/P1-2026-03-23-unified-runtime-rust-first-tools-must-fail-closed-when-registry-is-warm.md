## Bug Fix Record
- Categoria: A - Critico
- Bug: `UnifiedToolRuntime` continuava a lasciare una via di fuga verso i branch Swift locali per tool gia' classificati come Rust-first quando il registry MCP era gia' caldo ma l'alias Rust specifico mancava.
- Sintomo:
  - il path standard poteva ricadere su implementazioni locali Swift per tool come `grep` anche dopo warmup MCP;
  - il failure mode non veniva trattato come `mcp_unavailable` e non marcava il payload come MCP-backed.
- Impatto: ownership ibrida nascosta nel runtime tool, con rischio di drift tra routing Rust-first e comportamento effettivo del path standard.
- Gravita': P1
- Steps to reproduce:
  1. Scaldare `MCPNativeToolRegistry` con almeno un tool `coderide_*` valido.
  2. Invocare un tool canonico classificato Rust-first senza registrare il relativo alias MCP.
  3. Osservare che il runtime poteva ancora entrare nel branch Swift locale invece di fallire chiuso.
- Risultato attuale:
  - il gate iniziale preferiva Rust solo se il route esisteva;
  - in assenza di route, il runtime continuava nella validazione e nel dispatch locale;
  - il payload di errore non marcava sempre `is_mcp`.
- Risultato atteso:
  - se il registry MCP e' gia' caldo e un tool appartiene al perimetro Rust-first, l'assenza del route Rust deve produrre `mcp_unavailable`;
  - il payload deve restare marcato come `is_mcp=true`.
- Causa probabile:
  - il gate Rust-first distingueva solo il caso “route presente”, ma non il caso “registry caldo e route mancante”;
  - la classificazione del payload MCP nel `catch` non includeva questa forma di fail-closed.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Core/Execution/Dispatch/UnifiedToolRuntime+RunCoreDispatch.swift`
  - `Tests/CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests.swift`
- Non-scope:
  - ampliamento del catalogo Rust
  - rimozione completa dei branch Swift locali
  - UI/panel app-side
- Moduli confinanti da verificare:
  - `UnifiedToolRuntime+MCPCanonicalAliasRouting`
  - `UnifiedToolRuntimeMCPConsistencyTests`
  - contract MCP del runtime
- Test da aggiungere o aggiornare:
  - regressione che verifica `mcp_unavailable` + `is_mcp=true` quando il registry e' caldo ma l'alias del tool Rust-first manca.
- Strategia di fix minimo:
  - introdurre fail-closed prima del dispatch locale per i tool `shouldPreferRustAlias(...)` quando il registry e' caldo ma il route e' assente;
  - propagare `is_mcp` anche nel ramo di errore corrispondente.
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests`
- Commit previsto:
  - `fix(runtime): fail closed rust-first tools when alias route is missing`

## Stato
- corretto il 2026-03-23
