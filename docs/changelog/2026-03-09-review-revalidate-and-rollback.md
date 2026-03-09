# 2026-03-09 — Review revalidate e rollback patch workflow

## Obiettivo
Chiudere un altro pezzo del workflow canonico richiesto dal piano:
- revalidation esplicita dopo apply
- rollback esplicito di patch applicate

## Modifiche implementate

### ReviewPatchWorkflowService
- aggiunto `revalidatePatch(...)`
- aggiunto `rollbackPatch(...)`
- `revalidatePatch` riesegue la validation post-fix sul workspace corrente
- `rollbackPatch` applica la reverse patch quando i dati di rollback sono disponibili

### Command bus review / MCP
- aggiunti i nuovi comandi:
  - `review_revalidate_finding`
  - `review_rollback_patch`
- aggiornati:
  - catalogo tool MCP
  - allowlist IDE state
  - handler routing review
  - patch workflow handler
  - command dispatch nell’app

### Panel
- aggiunti pulsanti `Revalidate` e `Rollback` nel dettaglio finding del review panel
- il panel usa lo stesso path di servizio condiviso, non una logica alternativa

## Test eseguiti
- `CodeReviewHandlerTests/testReviewRevalidateFindingQueuesCommand`
- `CodeReviewHandlerTests/testReviewRollbackPatchQueuesCommand`
- risultato: verdi

## Impatto
- il review workflow ora espone esplicitamente due fasi che il piano richiedeva
- MCP, panel e backend condividono lo stesso percorso operativo per revalidation e rollback
