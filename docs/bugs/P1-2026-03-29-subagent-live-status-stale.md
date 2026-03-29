# P1 — Stato live sub-agent stale o duplicato

**Data:** 2026-03-29  
**Categoria:** A — Critico  
**Stato:** Corretto

## Problema

Le card dei sub-agent potevano rimanere in stato `running` anche dopo il completamento reale oppure comparire in più istanze con stato incoerente.

## Cause individuate

### 1. Status terminali troppo rigidi
- Il reducer trattava come terminali soprattutto `completed` e `failed`.
- Status equivalenti come `success`, `done`, `ok`, `finished` non chiudevano la card.

### 2. Identità provider duplicate
- Percorsi provider diversi potevano produrre eventi riferiti allo stesso sub-agent logico ma con `swarm_id` differente.
- In assenza di riconciliazione, l’evento terminale poteva aggiornare una card nuova invece di quella `running` già visibile.

## Fix applicato

- normalizzazione lifecycle dei valori terminali/running
- aliasing conservativo degli eventi duplicate verso la card live già esistente quando la firma identitaria è unica
- test di regressione per status terminali equivalenti e mismatch di `swarm_id`
