# P1 — I tool audit performance esistevano nel registry ma non venivano esposti nella sessione corrente

## Bug Fix Record
- Categoria: B
- Bug: i tool `audit_perf_*` erano definiti nel registry canonico e implementati nel core Rust, ma mancavano dal `ToolSchemaCatalog` usato per costruire i function tool della sessione.
- Sintomo: il runtime segnalava che i tool di audit performance non erano disponibili nella sessione corrente, anche se il progetto li supportava.
- Impatto: impossibilita' di invocare sempre i perf audit da sessioni tool-enabled; perdita di copertura analitica su performance e prompt fuorviante lato provider.
- Gravita': P1
- Steps to reproduce:
  1. Avviare una sessione tool-enabled che legge i tool dal `ToolSchemaCatalog`.
  2. Cercare o invocare `audit_perf_bottlenecks`, `audit_perf_memory`, `audit_perf_ui_responsiveness`, `audit_perf_startup` o `audit_perf_hot_paths`.
  3. Osservare che non compaiono tra i tool eseguibili della sessione.
- Risultato attuale: il registry canonico e il dispatcher Rust conoscono i perf audit, ma il catalogo schema non li esporta ai provider.
- Risultato atteso: tutti i tool `audit_perf_*` devono comparire nel catalogo schema ed essere sempre disponibili nelle sessioni che usano il function schema del workspace.
- Causa probabile: drift tra catalogo canonico/dispatcher audit e lista `auditTools` del `ToolSchemaCatalog`; inoltre la descrizione di `audit_run_profile` non documentava i profili performance supportati.
- Scope consentito:
  - `ToolSchemaCatalog+AuditTools`
  - `ToolSchemaCatalogTests`
  - documentazione bug/changelog correlata
- Non-scope:
  - refactor del runtime audit
  - modifiche al dispatcher Rust dei tool
  - ridefinizione dei profili audit oltre all'esposizione schema
- Moduli confinanti da verificare:
  - export OpenAI/Anthropic dei function tool
  - normalizzazione `knownExecutableToolNames()`
  - descrizione schema di `audit_run_profile`
- Test da aggiungere o aggiornare:
  - aggiornare il test dei tool richiesti nel catalogo includendo i `audit_perf_*`
  - aggiungere una regressione che verifichi i profili performance nella descrizione di `audit_run_profile`
- Strategia di fix minimo:
  - aggiungere i 5 perf audit a `auditTools`
  - allineare la descrizione di `audit_run_profile` ai profili performance supportati
  - evitare modifiche al dispatch/runtime dato che l'implementazione e' gia' presente
- Verifica post-fix:
  - `swift test --package-path CoderEngine --filter ToolSchemaCatalogTests`
- Commit previsto: `fix(audit): expose performance audit tools in session schemas`
