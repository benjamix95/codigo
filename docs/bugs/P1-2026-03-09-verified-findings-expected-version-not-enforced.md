# P1 — expectedEntityVersion non veniva applicato nel coordinatore comandi VerifiedFindings

## Categoria
Categoria A

## Bug
Il modello `VerifiedCommandMeta` esponeva `expectedEntityVersion`, ma `VerifiedFindingsCommandCoordinator` ignorava il campo e lasciava eseguire il comando anche con stato potenzialmente stale.

## Sintomo
Comandi critici potevano passare nel core shared senza alcun controllo di versione, nonostante il metadata fosse già presente.

## Impatto
Rischio di mutazioni concorrenti o stale write sui finding del canonical store, con perdita di garanzie sul contratto di concorrenza del piano.

## Gravità
Alta

## Riproduzione
1. Creare un `VerifiedCommandMeta` con `expectedEntityVersion`.
2. Eseguire il coordinatore con una versione reale diversa.
3. Osservare che, prima del fix, il comando veniva comunque eseguito.

## Causa probabile
Il coordinatore implementava deduplica e serializzazione per entity, ma non aveva ancora il gate esplicito di optimistic concurrency.

## Fix applicato
- aggiunto controllo opzionale `currentEntityVersion`
- errore esplicito `versionConflict`
- errore esplicito `versionUnavailable` se manca il provider di versione
- test di regressione per mismatch e match versione

## Regressione da coprire
- comando duplicato non rieseguito
- mismatch versione blocca il comando
- versione corretta consente l’operazione
