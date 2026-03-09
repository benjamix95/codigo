# P1 — Il gate quantitativo Security esisteva ma non bloccava `security_start`

## Categoria
Categoria A

## Bug
Il dominio `Security` aveva un gate quantitativo calcolato dal core shared, ma il tool MCP `security_start` lo ignorava e avviava comunque la review.

## Sintomo
`security_start` ritornava una sessione valida anche quando non esisteva alcuna baseline BugHunter verified o quando il gate risultava `blocked`.

## Impatto
Violazione diretta del requisito di rilascio: la pipeline `Security` risultava attivabile prima del superamento del gate quantitativo, con rischio di falsi positivi e rollout prematuro.

## Gravità
Alta

## Riproduzione
1. Avviare il server MCP senza snapshot `VerifiedFindings` pronte.
2. Invocare `security_start`.
3. Osservare che la sessione veniva accodata comunque.

## Causa probabile
Il gate era esposto nei read model e nei summary, ma non ancora trasformato in guardrail operativo nel routing MCP `Security`.

## Fix applicato
- `security_start` ora fallisce se il gate non è `ready`
- `security_status` mostra il gate anche senza sessione review attiva
- aggiunti test per gate bloccato, gate pronto e summary senza sessione attiva

## Regressione da coprire
- `security_start` bloccato senza baseline
- `security_start` consentito con gate ready
- `security_status` con gate summary anche in assenza di sessione
