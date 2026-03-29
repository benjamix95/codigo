# Bug Fix Record — 2026-03-29 — Riconciliazione stato live sub-agent

- **Categoria:** A — Critico
- **Bug:** le card dei sub-agent possono restare apparentemente `running` anche quando il sub-agent ha già terminato, oppure duplicarsi in più card con stato incoerente.
- **Sintomo:** nella chat e nello swarm panel restano card “appese”; l’utente non capisce se il sub-agent sta ancora lavorando o se ha già finito.
- **Impatto:** regressione UX su stato live, timeline rumorosa e possibile lettura errata del completamento reale del sub-agent.
- **Gravità:** Alta
- **Steps to reproduce:**
  1. Avviare un task con sub-agent via Codex o Claude.
  2. Lasciare che il provider emetta eventi di avvio/progresso e poi un evento terminale con `status` non perfettamente canonico, oppure con `swarm_id` diverso ma stessa identità logica.
  3. Osservare che la card live può restare in stato `running` o sdoppiarsi.
- **Risultato attuale:** alcuni terminal events non chiudono la card corretta; in certi casi si crea una nuova card invece di finalizzare quella già esistente.
- **Risultato atteso:** i terminal events devono chiudere la card corretta in tempo reale, anche se usano status terminali equivalenti (`success`, `done`, `ok`, `finished`) o arrivano da un percorso provider con `swarm_id` diverso ma stessa identità logica.
- **Causa probabile:**
  - il reducer riconosceva come terminali quasi solo `completed` / `failed`
  - mancava una riconciliazione tra eventi duplicati della stessa unità logica quando provider diversi o percorsi diversi emettevano `swarm_id` differenti
- **Scope consentito:** `SwarmLiveReducer`, helper di lifecycle/identity, test reducer e store swarm.
- **Non-scope:** UI card rendering, persistenza messaggi, protocollo eventi, provider transport, timeline interleaver.
- **Moduli confinanti da verificare:**
  - `SwarmLiveReducer`
  - `TaskActivityStore.swarmCardStates(...)`
  - test di store swarm scoped
- **Test da aggiungere o aggiornare:**
  - terminal status equivalenti a `completed`
  - aliasing tra `swarm_id` diversi ma stessa identità
  - store swarm scoped che continua a riflettere gli stati finalizzati
- **Strategia di fix minimo:**
  - normalizzare gli status lifecycle terminali e running in un helper dedicato
  - canonizzare gli eventi sub-agent prima del reduce, aliasando gli eventi duplicati verso la card live corretta quando la firma identitaria è unica
  - mantenere il reducer principale compatto, spostando helper puri in file separati
- **Verifica post-fix:**
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SwarmLiveReducerTests -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests`
- **Commit previsto:** `fix(swarm): reconcile live subagent terminal states`

## Bug trovati in questo intervento

### P1 — Status terminali non canonici non chiudono la card live
- **Stato:** Risolto
- **Dettaglio:** `success`, `done`, `ok`, `finished` non venivano trattati come terminali dal reducer.

### P1 — Doppia identità dello stesso sub-agent lascia card running stale
- **Stato:** Risolto
- **Dettaglio:** eventi con `swarm_id` diversi ma stessa identità logica potevano creare una card nuova invece di finalizzare quella esistente.
