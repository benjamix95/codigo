# Bug Fix Record — Chat live snapshot staleness broke interleaving and subagent cards

## Bug Fix Record

- **Categoria:** A — Critico
- **Bug:** il refresh live task/swarm poteva leggere `messagesConversationSnapshot` stantia invece della conversazione più fresca del `ChatStore`
- **Sintomo:** in Codex e Claude i tool risultavano eseguiti ma la chat restava monolitica o in ritardo nell’interleaving; inoltre i subagent partivano ma card e transcript non comparivano in chat
- **Impatto:** perdita di causalità `text/tool/text`, riduzione forte di osservabilità e regressione UX sul flusso core agentico
- **Gravità:** P1 — Critico
- **Steps to reproduce:**
  1. avviare una chat agentica con tool trace e/o subagent live
  2. avere eventi task/swarm in arrivo mentre `messagesConversationSnapshot` non è ancora riallineata allo store
  3. lasciare che `scheduleLiveActivitySnapshotRefresh` esegua `refreshTaskActivityDependentSnapshots`
  4. osservare che il refresh usa la snapshot già presente invece della conversazione store aggiornata
  5. verificare che la chat non mostri subito i marker tool o le live card subagent
- **Risultato attuale:** i refresh live preferiscono la conversazione del `ChatStore` quando disponibile per il thread selezionato; in fallback usano la snapshot solo se lo store non ha ancora il thread corretto
- **Risultato atteso:** tool trace e swarm card devono proiettarsi sullo stesso assistant turn attivo, senza dipendere da una snapshot vecchia
- **Causa probabile:** il path `refreshTaskActivityDependentSnapshots` combinava throttling burst-safe con una scelta errata della sorgente, preferendo `messagesConversationSnapshot` anche quando lo store possedeva già dati più freschi
- **Scope consentito:**
  - `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/*`
  - `App/SoloCodeApp/Sources/Services/ChatThread/Support/*`
  - test policy snapshot/live refresh
- **Non-scope:**
  - MCP server e tool catalog
  - transport/provider CLI Codex/Claude
  - refactor del renderer timeline
- **Moduli confinanti da verificare:**
  - `refreshMessagesSnapshot`
  - `ChatStreamingTimelineTurnResolver`
  - `visibleSwarmCardsForChat`
- **Test da aggiungere o aggiornare:**
  - policy che preferisce la conversazione store del thread selezionato
  - fallback alla snapshot solo quando lo store non ha la conversazione
  - rifiuto di conversazioni appartenenti a thread diversi
- **Strategia di fix minimo:** introdurre una policy pura per scegliere la conversazione corretta e usarla nel refresh live task/swarm; se lo store contiene già il thread attivo, forzare `refreshMessagesSnapshot()` così trace e live card si riallineano allo stesso assistant turn
- **Verifica post-fix:**
  - test mirati `ChatTaskActivitySnapshotRefreshPolicyTests`
  - smoke mirato chat/subagent su `xcodebuild test` del target app
- **Commit previsto:** `fix(chat): prefer fresh store conversation for live task snapshots`
