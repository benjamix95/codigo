# ARCH — Dual-storage senza meccanismo di riconciliazione

## Analisi architetturale

### Descrizione
L'intero layer di stato condiviso (bug hunter snapshots, code review snapshots, verified findings) usa un pattern dual-write: prima nel PostgresPersistenceStore, poi nei file JSON su disco. I read preferiscono il persistence store e cadono su disco se non disponibile.

### Problema fondamentale
Non esiste:
- Transazione distribuita tra i due store
- Version vector o sequence number per confrontare chi è più aggiornato
- Meccanismo di riconciliazione quando i due store divergono
- Strategia di conflict resolution

### Scenari di failure
1. **Persistence write OK, file write FAIL** → persistence ahead, disco stale. Se persistence va giù, read da disco ritorna dati vecchi.
2. **Persistence write FAIL, file write OK** → disco ahead. Persistence non ha i dati più recenti.
3. **Persistence intermittente** → alcune write vanno su entrambi, altre solo su disco. I due store hanno subset diversi dei dati.
4. **Delete inconsistente** → `deleteCodeReviewSession` elimina da persistence e poi da disco. Se crash tra i due, ghost session su disco.

### Raccomandazione
**Short term:** Aggiungere `mutationSequence` incrementale a ogni write. Sul read, confrontare le versioni dei due store e prendere la più alta.

**Long term:** Scegliere un single source of truth (persistence store) con disco come write-ahead log di fallback, e implementare reconciliation on-startup.
