# P0 — Command queue unbounded growth (BugHunter + CodeReview)

## Bug Fix Record
- Categoria: A - Critico
- Bug: le code di comandi BugHunter e CodeReview crescono indefinitamente nel file JSON. I comandi completati/falliti non vengono mai rimossi.
- Sintomo: dopo settimane di uso, `commands.json` diventa molto grande. Ogni operazione read/deserialize/write diventa lenta. Rischio di out-of-memory o timeout su file molto grandi.
- Impatto: degradazione progressiva delle performance dei tool MCP BugHunter e CodeReview. In casi estremi, timeout o crash.
- Gravita: P0
- Steps to reproduce:
  1. Eseguire centinaia di comandi BugHunter/CodeReview nel tempo.
  2. Verificare la dimensione di `commands.json` — cresce solo, non si riduce mai.
- Risultato attuale: comandi terminali (completed/failed/cancelled) restano nel file per sempre.
- Risultato atteso: comandi terminali piu vecchi di 24h vengono automaticamente rimossi. La coda e limitata a 200 comandi totali.
- Causa probabile: nessuna logica di pruning implementata in `writeBugHunterCommandsUnsafe` ne in `_writeCodeReviewCommandsUnsafe`.
- Scope consentito: `MCPSharedState+BugHunterCommands.swift`, `MCPSharedState+CodeReviewCommands.swift`
- Non-scope: formato JSON, logica di enqueue/claim, persistenza Postgres
- Moduli confinanti da verificare: polling dei comandi dal Rust MCP server, UI che mostra lo stato dei comandi
- Test da aggiungere o aggiornare: test di pruning che verifica rimozione comandi vecchi e cap a 200
- Strategia di fix minimo:
  - Aggiungere `prunedCommands()` che filtra comandi terminali > 24h e limita a 200 totali
  - Chiamare il pruning in `write*CommandsUnsafe` prima della serializzazione
- Verifica post-fix: build success + verifica che la funzione di pruning viene chiamata ad ogni write
- Commit previsto: `fix(mcp): add command queue pruning to prevent unbounded growth`

## Fix applicato
- `MCPSharedState+BugHunterCommands.swift`: aggiunto `prunedCommands()` + chiamata in `writeBugHunterCommandsUnsafe`
- `MCPSharedState+CodeReviewCommands.swift`: aggiunto `_prunedReviewCommands()` + chiamata in `_writeCodeReviewCommandsUnsafe`
- Parametri: `maxCompletedCommandAge = 86_400` (24h), `maxCommandQueueSize = 200`
