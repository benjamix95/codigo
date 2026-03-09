# P1 — I workflow review usavano il coordinatore shared senza passare la versione del finding

## Categoria
Categoria A

## Bug
I path applicativi `review` passavano dal `VerifiedFindingsCommandCoordinator`, ma costruivano `VerifiedCommandMeta` con `expectedEntityVersion = nil`.

## Sintomo
Il coordinatore aveva il guard di versione, ma i workflow review/patch non gli fornivano mai la versione attesa del finding.

## Impatto
I comandi critici continuavano a comportarsi come se il guard di optimistic concurrency non esistesse, lasciando aperto il rischio di stale command sui finding.

## Gravità
Alta

## Riproduzione
1. Costruire un `MCPSharedCodeReviewCommand` che agisce su un finding shared.
2. Passarlo al workflow review.
3. Osservare che il `VerifiedCommandMeta` non contiene la versione attesa del finding.

## Causa probabile
Il bridge review verso `VerifiedFindings` era stato aggiornato a usare il coordinatore shared prima che il versioning del finding diventasse persistente e incrementale.

## Fix applicato
- il sync service ora preserva e incrementa la `version` dei finding nel canonical snapshot
- i path review costruiscono `VerifiedCommandMeta` con `expectedEntityVersion`
- il coordinatore riceve anche una closure `currentEntityVersion` per confrontare la versione corrente sotto lock

## Regressione da coprire
- sync service: versione invariata se il finding non cambia
- sync service: versione incrementata se il lifecycle cambia
- integrazione app: pipeline review continua a produrre sessioni `VerifiedFindings` coerenti
