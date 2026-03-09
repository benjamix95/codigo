# P1 — BugHunter deduplica in modo incoerente il commit primario

## Bug Fix Record
- Categoria: B
- Bug: il commit primario di un run BugHunter viene salvato in forma incoerente rispetto alla chiave usata dalla deduplica.
- Sintomo: run sullo stesso commit possono non essere deduplicati correttamente oppure generare riesecuzioni non deterministiche.
- Impatto: rumore operativo, risultati duplicati, storico meno affidabile.
- Gravita': P1
- Steps to reproduce:
  1. Avviare un run BugHunter basato su commit.
  2. Confrontare il valore persistito del commit primario con la chiave usata dal matcher di deduplica.
  3. Ripetere il run sullo stesso commit.
- Risultato attuale: il run puo' usare `againstRefExpression` come valore persistito mentre la deduplica confronta lo SHA reale.
- Risultato atteso: persistenza e deduplica devono usare la stessa identita' del commit.
- Causa probabile: sovrapposizione tra semantica "against ref" e semantica "primary commit" nel modello di run.
- Scope consentito: servizi/handler BugHunter e modelli snapshot correlati.
- Non-scope: modifica dell'intero modello code review `against_ref`.
- Moduli confinanti da verificare: run history, status read, commit-window logic.
- Test da aggiungere o aggiornare:
  - test di deduplica su stesso commit SHA
  - test che distingua correttamente `against_ref` e `primary_commit`
- Strategia di fix minimo:
  - normalizzare la persistenza del commit primario su SHA canonico
  - usare la stessa chiave per snapshot, status e deduplica
- Verifica post-fix:
  - test run history e deduplica
  - smoke su `bughunter_start` e `bughunter_commit_window`
- Commit previsto: `fix(bughunter): align primary commit identity with dedupe`
