# P0 — Command queue bug hunter e code review cresce senza limiti

## Bug Fix Record
- Categoria: A - Critico
- Bug: Le code di comandi in `MCPSharedState+BugHunterCommands.swift` e `MCPSharedState+CodeReviewCommands.swift` non effettuano pruning di comandi completati, falliti o scaduti. Il file `commands.json` cresce indefinitamente.
- Sintomo: Dopo settimane di uso, `commands.json` contiene migliaia di comandi vecchi. Ogni operazione legge l'intero file, lo deserializza, e lo riscrive. Performance degradano progressivamente.
- Impatto: Lock hold time crescente (il file lock è tenuto durante l'intera lettura/deserializzazione/scrittura), latenza delle operazioni MCP in aumento, consumo memoria crescente.
- Gravità: P0
- Steps to reproduce:
  1. Usare bug hunter e code review per diverse sessioni di lavoro.
  2. Dopo 50+ sessioni, misurare la dimensione di `commands.json`.
  3. Osservare la latenza delle operazioni di enqueue/dequeue.
- Risultato attuale: I comandi completati e falliti restano nel file per sempre. Solo i comandi "stale" vengono riciclati dopo timeout (3605s per bughunter, 120s per review), ma non rimossi.
- Risultato atteso: Pruning automatico dei comandi completati/falliti. Configurabile con un cap massimo (es. ultimi 100 comandi) o una finestra temporale (es. comandi degli ultimi 7 giorni).
- Causa probabile: Il pruning non è stato implementato nel design iniziale.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+BugHunterCommands.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CodeReviewCommands.swift`
- Non-scope: logica di enqueue/dequeue, format del file, persistence store.
- Moduli confinanti da verificare: Rust MCP server (legge gli stessi file), `MCPSharedState+RustReviewQueue.swift`, `MCPSharedState+RustBugHunterQueue.swift`.
- Test da aggiungere o aggiornare:
  - Test: dopo pruning, comandi recenti sono preservati.
  - Test: comandi completati > 24h vengono rimossi.
  - Test: comandi pending non vengono mai rimossi dal pruning.
- Strategia di fix minimo: Aggiungere un `pruneStaleCommands()` chiamato ad ogni write, che rimuove comandi con status `completed`/`failed` più vecchi di 24 ore e limita il totale a 200 comandi (mantenendo i più recenti).
- Verifica post-fix:
  1. Unit test pruning con comandi misti.
  2. Build + test suite.
  3. Smoke test: dopo molte sessioni il file resta di dimensione ragionevole.
- Commit previsto: `fix(mcp-shared-state): add automatic pruning for command queues`
