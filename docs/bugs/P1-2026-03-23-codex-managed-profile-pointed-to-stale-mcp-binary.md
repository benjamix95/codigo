## Bug Fix Record
- Categoria: A - Critico
- Bug: il profilo Codex gestito poteva puntare a un `coderide-mcp-server-rust` stale/non esistente, lasciando Codex senza server MCP effettivamente disponibile.
- Sintomo: `mcpServerStatus/list` mostrava `coderide` presente ma con `tools = {}` oppure Codex ricadeva su tool interni/shell.
- Impatto: anche con profilo e auth corretti, i tool MCP di progetto non erano disponibili al modello.
- Gravità: P1
- Steps to reproduce:
  1. Avere un profilo `_default` creato quando il binario MCP era in un path temporaneo o derivato da build non più esistenti.
  2. Avviare Codex con quel `CODEX_HOME`.
  3. Verificare che `coderide` sia configurato ma senza tool caricati.
- Risultato attuale: il resolver del binario considerava solo override esplicito e bundle sibling, lasciando il profilo su path stale.
- Risultato atteso: in sviluppo il resolver deve trovare il binario MCP più recente disponibile nel repo o nel bundle.
- Causa probabile: risoluzione troppo stretta del path del binario MCP e mancanza di fallback verso i build artifact di sviluppo.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+Paths.swift`
  - `Tests/SoloCodeAppTests/CLIProfileProvisionerTests.swift`
- Non-scope:
  - refactor del lifecycle MCP
  - cambi al protocollo app-server
- Moduli confinanti da verificare:
  - profilo `_default`
  - seeding/repair `config.toml`
  - mcp server status lato Codex
- Test da aggiungere o aggiornare:
  - fallback path di sviluppo sceglie il binario più recente
- Strategia di fix minimo:
  - cercare il binario `coderide-mcp-server-rust` anche nei build artifact del repo
  - scegliere il candidate eseguibile più recente
- Verifica post-fix:
  - test Swift mirato sul resolver
  - smoke `codex app-server` con `mcpServerStatus/list`
- Commit previsto:
  - fix(codex): prefer newest available coderide mcp binary
