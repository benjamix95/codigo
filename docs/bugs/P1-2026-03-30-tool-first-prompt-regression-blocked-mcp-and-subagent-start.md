# Bug Fix Record — Tool-first prompt regression blocked MCP and subagent start

## Bug Fix Record

- **Categoria:** A — Critico
- **Bug:** i prompt runtime di Codex/Claude imponevano ancora un preambolo user-facing prima dei tool operativi e della delega `subagent_*`
- **Sintomo:** dopo la richiesta il modello rispondeva con testo come “Ricevuto”, “Ingerisco la policy”, “Analizzo…”, invece di partire subito con `policy_ack`, MCP tool o `subagent_*`; in molti casi i subagent non venivano avviati affatto
- **Impatto:** regressione del flusso tool-first, MCP percepiti come lenti/non usati, subagent Codex/Claude non avviati nel round corretto
- **Gravità:** P1 — Critico
- **Steps to reproduce:**
  1. aprire una chat con Codex o Claude su un task che richiede tool MCP o subagent
  2. avere un marker `policy_ack` obbligatorio o una richiesta che beneficia di delega
  3. osservare che il modello emette prima una frase naturale di “acknowledgment”
  4. verificare che il primo round non parta subito con i tool e che la delega possa degradare o saltare
- **Risultato attuale:** i prompt richiedono esecuzione tool-first; `policy_ack` va emesso in modo silenzioso e diretto, senza testo filler; la delega `subagent_*` può partire subito nel primo round operativo
- **Risultato atteso:** nessuna frase intermedia prima dei tool MCP o dei subagent quando il passo successivo è già noto
- **Causa probabile:** accumulo di policy testuali che chiedevano “acknowledge policy ingestion”, “user-facing update first” e “todo before any work”, inducendo il modello a verbalizzare invece di chiamare i tool
- **Scope consentito:**
  - prompt/policy condivisi `ToolEnabledLLMProvider`
  - prompt provider-specific Codex/Claude
  - template istruzioni persistite
  - test prompt/policy
- **Non-scope:**
  - MCP server implementation
  - runtime subagent backend
  - renderer chat
- **Moduli confinanti da verificare:**
  - `InstructionPolicyBundle`
  - `ToolEnabledLLMProvider+Policy`
  - `codex_app_server_prompt.rs`
  - `claude.rs`
- **Test da aggiungere o aggiornare:**
  - bundle policy con ack silenzioso
  - prompt subagent senza `USER-FACING UPDATE FIRST`
  - template profilo con divieto esplicito di filler prima dei tool
  - prompt Rust Claude/Codex coerenti
- **Strategia di fix minimo:** rimuovere l’obbligo di aggiornamento testuale prima dei tool, rendere `policy_ack` esplicitamente silenzioso e imporre l’avvio diretto di `coderide_*`, `mcp__coderide__*` e `subagent_*`
- **Verifica post-fix:**
  - `cargo test --manifest-path Native/RustCore/Cargo.toml coderide_system_prompt_starts_with_tools_not_filler -- --nocapture`
  - `xcodebuild test ... -only-testing:CoderEngineTests/InstructionPolicyBundleTests`
  - `xcodebuild test ... -only-testing:CoderEngineTests/ToolEnabledLLMProviderSubagentPolicyTests`
  - `xcodebuild test ... -only-testing:SoloCodeAppTests/CLIProfileProvisionerInstructionSyncSubagentRoutingTests`
- **Commit previsto:** `fix(prompt): enforce silent policy ack and tool-first subagent start`
