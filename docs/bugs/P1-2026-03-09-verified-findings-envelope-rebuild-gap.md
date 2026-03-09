# P1 — VerifiedFindings perdeva la projection se mancava l'envelope derivato

## Categoria
Categoria A

## Bug
Il backend shared `VerifiedFindings` persisteva l'envelope sessione, ma non offriva un fallback robusto per rigenerarlo dal canonical store se il file derivato spariva o si corrompeva.

## Sintomo
Una lettura `readVerifiedFindingsEnvelope(sessionId:)` falliva quando mancava il file in `verified-findings/sessions/<session>.json`, anche se la snapshot canonica del run poteva ancora essere disponibile.

## Impatto
Perdita operativa della projection per panel/chat/main chat, con rischio di stato “sparito” pur avendo ancora i dati di dominio persistiti.

## Gravità
Alta

## Riproduzione
1. Salvare una sessione `VerifiedFindings`.
2. Eliminare il file envelope derivato.
3. Tentare la lettura del backend shared.
4. Osservare il fallback mancante e l'assenza della projection ricostruita.

## Causa probabile
Persistenza troppo centrata sull'envelope derivato e checkpoint insufficiente del canonical store.

## Fix applicato
- persistenza esplicita della snapshot canonica `VerifiedFindings`
- persistenza di un checkpoint schema-aware con conteggi e versioni
- fallback di rebuild dell'envelope direttamente dal canonical store tramite `VerifiedFindingsProjectionBuilder`

## Regressione da coprire
- roundtrip envelope
- rebuild da canonical snapshot
- roundtrip checkpoint
- fallback da `CodeReviewSessionSnapshot` verso envelope ricostruito
