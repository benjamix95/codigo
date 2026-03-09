# P2 — Mancavano workflow service di dominio per Security e BugHunter sopra il core shared

## Categoria
Categoria B

## Bug
Anche dopo il rollout di facade, query e lifecycle shared, `Security` e `BugHunter` non avevano ancora workflow service di dominio propri. Gli handler continuavano a comporre da soli query/gate/lifecycle.

## Sintomo
La logica shared esisteva, ma i path MCP `security_*` e `bughunter_*` rimanevano ancora troppo “handler-centrici”.

## Impatto
Manutenibilità bassa e rischio di drift tra i due domini, pur avendo il core `VerifiedFindings` già abbastanza maturo.

## Gravità
Media

## Riproduzione
1. Ispezionare gli handler `Security` e `BugHunter`.
2. Osservare che parte della logica di dominio era ancora assemblata localmente.

## Causa probabile
Il core shared è stato estratto per tranche; i wrapper di dominio sono arrivati dopo facade/query/lifecycle.

## Fix applicato
- aggiunti `SecurityWorkflowService` e `BugHunterWorkflowService`
- gli handler `security_*` e `bughunter_*` usano ora questi service per gate/findings/cluster/lifecycle più spesso
- ridotto ancora l’accoppiamento residuo al modello review raw
