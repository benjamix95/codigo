## Bug Fix Record
- Categoria: A - Critico
- Bug: il main chat Codex poteva entrare nel transport Rust anche quando il unified tool runtime era attivo, saltando il path Swift `ToolEnabledLLMProvider` che applica registry MCP, policy `policy_ack` e enforcement `coderide_*`.
- Sintomo: Codex nel main chat non usava in modo affidabile i tool MCP/progetto provisionati dall'app e poteva continuare a dipendere dal comportamento della CLI nativa.
- Impatto: il backend Codex risultava meno allineato a Claude/Gemini/OpenAI nel rispetto del catalogo tool del progetto.
- Gravità: P1
- Steps to reproduce:
  1. Abilitare `ReviewCoreBridge`.
  2. Selezionare `codex-cli` nel main chat con `unifiedToolRuntimeEnabled = true`.
  3. Inviare un task operativo nel main chat.
- Risultato attuale: il path Rust costruiva una sessione `codex exec --json` senza mediazione tool equivalente al wrapper Swift e senza un `CODEX_HOME` gestito di default fuori dal multi-account.
- Risultato atteso: Codex deve usare il profilo gestito dall'app con `coderide` provisionato e, nel main chat con runtime unificato attivo, deve restare sul path Swift tool-enabled.
- Causa probabile: il resolver del transport Rust non distingueva il caso Codex+runtime unificato, mentre `ProviderFactory.codexProvider` non imponeva un `CODEX_HOME` gestito quando non erano attivi account CLI multipli.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner.swift`
  - `App/SoloCodeApp/Sources/Settings/ProviderFactory/Utility/ProviderFactory+SharedUtilities.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/ChatPanelView+PartN_RuntimeTransportSelection.swift`
  - test mirati correlati
- Non-scope:
  - refactor del backend Rust Codex
  - nuovo transport app-server/dynamic-tools
  - cambiamenti ai backend Claude/Gemini/OpenAI
- Moduli confinanti da verificare:
  - provisioning profili Codex
  - provider factory runtime parity
  - selezione transport Rust main chat
- Test da aggiungere o aggiornare:
  - default managed Codex profile path
  - default `CODEX_HOME` injection
  - bypass Rust transport per Codex con runtime unificato
- Strategia di fix minimo:
  - introdurre un profilo Codex gestito di default (`_default`) per ottenere sempre `CODEX_HOME` provisionato dall'app
  - bypassare il transport Rust solo per Codex quando il unified tool runtime è attivo
- Verifica post-fix:
  - test unitari mirati su provisioning, provider factory e runtime transport
- Commit previsto:
  - fix(codex): keep main chat on managed tool runtime and default managed profile
