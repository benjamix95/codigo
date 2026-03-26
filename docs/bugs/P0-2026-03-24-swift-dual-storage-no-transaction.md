# P0 — Dual-storage (Persistence + JSON files) senza consistenza transazionale

## Bug Fix Record
- Categoria: A - Critico
- Bug: L'architettura scrive sia nel PostgresPersistenceStore che nei file JSON su disco, senza transazione distribuita né meccanismo di riconciliazione. Se una delle due write fallisce, i due store divergono.
- Sintomo: Ghost sessions (sessioni che appaiono/scompaiono a seconda di quale store viene letto), dati stale quando il persistence store è intermittente, perdita silenziosa di snapshot.
- Impatto: Stato inconsistente tra i due store. Quando il persistence store è indisponibile e poi ritorna, può servire dati vecchi sovrascrivendo quelli nuovi scritti solo su disco.
- Gravità: P0
- Steps to reproduce:
  1. Persistence store disponibile → write va su entrambi.
  2. Persistence store diventa indisponibile → write va solo su disco.
  3. Persistence store ritorna → read prende dati stale dal persistence store.
- Risultato attuale: Pattern in `writeBugHunterSnapshot`, `writeCodeReviewSnapshot`, `deleteCodeReviewSession`:
  ```
  try? store.persist(...)  // persistence store (fuori lock)
  withFileLock {
      data.write(to: file)  // disco (dentro lock)
  }
  ```
  Nessuna transazione, nessun rollback, nessun version vector.
- Risultato atteso: Almeno uno dei seguenti:
  - Write atomica: se una fallisce, l'altra viene rollbackata.
  - Version vector: i read confrontano le versioni dei due store e prendono la più recente.
  - Single source of truth: eliminare il dual-write e usare un solo store primario con fallback read-only.
- Causa probabile: Il persistence store è stato aggiunto come layer di ottimizzazione sopra il file system, ma senza gestire i casi di failure parziale.
- Scope consentito: Questo è un problema architetturale trasversale. Il fix minimo dovrebbe essere in:
  - `MCPSharedState+BugHunter.swift`
  - `MCPSharedState+CodeReview.swift`
  - `MCPSharedState+VerifiedFindings.swift`
- Non-scope: Redesign completo del persistence layer, migrazione a un unico store.
- Moduli confinanti da verificare: tutti i read path (che preferiscono persistence store), tutti i write path, `PersistenceBridge`.
- Test da aggiungere o aggiornare:
  - Test: persistence store fallisce → dati recuperabili da disco.
  - Test: persistence store ritorna dopo downtime → non sovrascrive dati più recenti da disco.
- Strategia di fix minimo: Aggiungere un `mutationSequence` (contatore incrementale) a ogni snapshot. Sul read, confrontare la versione tra persistence store e disco e prendere la più alta. Questo non risolve il problema completamente ma mitiga il caso più comune.
- Verifica post-fix:
  1. Test con persistence store intermittente → dati corretti.
  2. Build + test suite.
- Commit previsto: `fix(mcp-shared-state): add mutation sequence to dual-storage reads`
