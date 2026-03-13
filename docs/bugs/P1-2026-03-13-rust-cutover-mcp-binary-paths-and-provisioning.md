# P1 - Provisioning e script continuavano a trattare `coderide-mcp-server` come binario MCP canonico

## Bug Fix Record
- Categoria: A - Critico
- Bug: profili gestiti, script di build/validazione bundle, detection MCP e harness di test continuavano a puntare al nome legacy `coderide-mcp-server` invece del binario Rust canonico `coderide-mcp-server-rust`.
- Sintomo: il repo poteva ancora provisionare config o test harness che cercavano il binario legacy, mantenendo vivo un path Swift non piu' desiderato.
- Impatto: cutover MCP ambiguo, rischio di bootstrap verso artefatti legacy e impossibilita' di affermare che il runtime MCP fosse davvero Rust-only.
- Gravita': alta
- Steps to reproduce:
  1. Provisionare un profilo Codex/Claude/Gemini gestito.
  2. Osservare fallback o sibling path costruiti verso `coderide-mcp-server`.
  3. Eseguire gli script di bundle/test e notare che alcuni lookup cercavano ancora il nome legacy.
- Risultato attuale: tutti i path gestiti devono puntare a `coderide-mcp-server-rust`; il binario legacy non deve piu' essere richiesto come artefatto canonico.
- Risultato atteso: provisioning, lookup test, cache bypass MCP e validazione bundle usano solo il binario Rust.
- Causa probabile: tranche precedenti avevano mantenuto un alias legacy per compatibilita' temporanea.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Accounts/Provisioning/*`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/Lifecycle/MCPSessionManager+Lifecycle.swift`
  - `scripts/build_rust_mcp_server.sh`
  - `scripts/validate_app_bundle.sh`
  - test provisioning/MCP correlati
- Non-scope:
  - rimozione completa degli handler Swift statici del target `CoderIDEMCPServer`
  - rimozione del target/framework dal progetto Xcode
- Moduli confinanti da verificare:
  - `CLIProfileProvisionerTests`
  - `MCPSessionManagerTests`
  - `ToolEnabledLLMProviderMCPWarmupTests`
  - app bundle validation scripts
- Test da aggiungere o aggiornare:
  - fallback Codex assoluto aggiornato al binario Rust
  - lookup test `.build` aggiornato al binario Rust
  - cache bypass MCP basato sul comando Rust
- Strategia di fix minimo:
  - sostituire i path legacy con il nome Rust
  - rimuovere la copia dell’alias legacy negli artifact di build MCP
  - rendere il `CoderIDEMCPServerApp.main()` Swift un fail-fast esplicito per evitare riattivazioni accidentali
- Verifica post-fix:
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- Commit previsto: `refactor(rust-cutover): normalize mcp provisioning on rust binary`

## Note
- Restano ancora handler statici Swift nel target `CoderIDEMCPServer` usati soprattutto da test e compat layer; questo slice rimuove pero' il ruolo del binario legacy come runtime canonico.
