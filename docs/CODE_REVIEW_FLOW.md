# Flusso di Code Review

Questo documento descrive come funziona il flusso di code review nel progetto, dalla preparazione fino al merge.

## 1. Preparazione della modifica

- Mantieni la PR piccola e focalizzata su un singolo obiettivo.
- Aggiorna il branch partendo dall'ultima `main`.
- Esegui test e lint in locale prima di chiedere review.
- Evita commit rumorosi: separa refactor, fix e feature quando possibile.

## 2. Apertura della Pull Request

La PR deve contenere:

- Contesto: problema da risolvere e motivazione.
- Soluzione: cosa è stato cambiato e perché.
- Impatto: aree toccate, rischi, compatibilità.
- Verifica: test eseguiti e relativo esito.
- Eventuali screenshot/log se utili.

## 3. Checklist minima dell'autore

Prima di assegnare i reviewer:

- Il codice compila senza warning rilevanti.
- I test passano (unit/integration, se applicabili).
- Non ci sono secret o credenziali nel diff.
- Naming, stile e struttura sono coerenti con il progetto.
- La documentazione è aggiornata se il comportamento cambia.

## 4. Processo di review

Il reviewer controlla in ordine:

- Correttezza funzionale: la modifica risolve davvero il problema.
- Regressioni: casi limite, side effects, backward compatibility.
- Sicurezza e robustezza: validazioni input, gestione errori.
- Leggibilità e manutenibilità: semplicità, coerenza, duplicazioni.
- Copertura test: presenza e qualità dei test sulle parti critiche.

## 5. Tipi di feedback

Usare commenti chiari e azionabili:

- **Blocking**: problema che deve essere risolto prima del merge.
- **Non-blocking**: miglioramento consigliato ma non obbligatorio.
- **Question**: dubbio tecnico da chiarire.
- **Nit**: dettaglio di stile/minore.

## 6. Gestione delle modifiche richieste

- L'autore risponde ai commenti uno per uno.
- Applica fix in commit tracciabili.
- Riesegue test/lint dopo le modifiche.
- Chiede nuova review solo quando i punti bloccanti sono chiusi.

## 7. Criteri di approvazione

La PR può essere approvata quando:

- Tutti i commenti blocking sono risolti.
- Le pipeline CI richieste sono verdi.
- La descrizione PR è aggiornata e coerente con il diff finale.

## 8. Merge e post-merge

- Esegui squash/rebase/merge secondo convenzione del repository.
- Verifica che il branch venga sincronizzato con `main`.
- Se necessario, monitora regressioni subito dopo il merge.

## 9. Regole pratiche consigliate

- PR piccole (idealmente sotto ~400 righe modificate).
- Preferire discussioni tecniche su trade-off, non solo sullo stile.
- Criticare il codice, non la persona.
- Se una scelta è non ovvia, documentare il motivo nel codice o nella PR.

---

## Template rapido per PR

```md
## Contesto
<problema e obiettivo>

## Soluzione
<cosa hai cambiato>

## Impatto
<moduli/aree coinvolte + rischi>

## Verifiche eseguite
- [ ] build locale
- [ ] test unitari
- [ ] lint/format

## Note review
<punti su cui vuoi feedback mirato>
```
