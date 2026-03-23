## Bug Fix Record
- Categoria: A - Critico
- Bug: il profilo Codex gestito `_default` non sincronizzava `auth.json` dal profilo globale `~/.codex`, causando richieste `401 Unauthorized` dopo il forcing di `CODEX_HOME`.
- Sintomo: il main chat Codex partiva, apriva il thread, poi falliva con `Missing bearer or basic authentication in header` verso `https://api.openai.com/v1/responses`.
- Impatto: Codex risultava inutilizzabile nel path gestito dell'app finché l'utente non effettuava un nuovo login esplicitamente dentro il profilo `_default`.
- Gravità: P1
- Steps to reproduce:
  1. Avere Codex loggato nel profilo globale `~/.codex`.
  2. Avviare SoloCode dopo il forcing del `CODEX_HOME` gestito.
  3. Eseguire un task con `codex-cli`.
- Risultato attuale: SoloCode lanciava Codex con `CODEX_HOME` puntato al profilo `_default`, ma quel profilo non conteneva `auth.json`.
- Risultato atteso: il profilo `_default` deve ereditare l'autenticazione valida già presente nel profilo globale, almeno quando non ha ancora credenziali locali.
- Causa probabile: il provisioning del profilo `_default` creava `config.toml`/`AGENTS.md`/`instructions.md` ma non sincronizzava i token Codex globali.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner.swift`
  - `Tests/SoloCodeAppTests/CLIProfileProvisionerTests.swift`
- Non-scope:
  - refactor del login Codex multi-account
  - modifica del formato auth della Codex CLI
  - cambiamenti ai backend non-Codex
- Moduli confinanti da verificare:
  - seeding del profilo `_default`
  - presenza/validità di `auth.json`
  - regressione dei test di provisioning Codex
- Test da aggiungere o aggiornare:
  - copia di `auth.json` globale nel profilo `_default` gestito
- Strategia di fix minimo:
  - sincronizzare `auth.json` dal profilo globale al profilo `_default` solo quando la sorgente è valida e il target manca o è più vecchio/non valido
- Verifica post-fix:
  - test mirato `CLIProfileProvisionerTests`
- Commit previsto:
  - fix(codex): sync default managed profile auth
