# P2 — Il query layer shared aveva rotto la redazione compatibile di `review_findings`

## Categoria
Categoria B

## Bug
Il nuovo `VerifiedFindingsQueryService` produceva `file_label` e `message_summary` non compatibili con il contratto storico di `review_findings`.

## Sintomo
I test di regressione review fallivano perché l’output non mostrava più:
- prefisso `redacted-...`
- summary `Redacted ... finding`

## Impatto
Rischio di leak informativo e rottura della UI/test suite di review findings.

## Gravità
Media

## Causa probabile
Il query layer era corretto sul piano architetturale, ma non aveva ancora allineato il formato di redazione al comportamento esistente.

## Fix applicato
- ripristinata la redazione compatibile nel query service
- `review_findings` torna a omettere dettagli sensibili mantenendo il formato storico

## Regressione da coprire
- review findings senza file path reali
- summary redatto
- fallback session resolution senza leak del messaggio originale
