# P2 — L'assemblaggio dello status VerifiedFindings era ancora sparso tra MCP e superfici secondarie

## Categoria
Categoria B

## Bug
Anche dopo facade/query/workflow service, lo status della pipeline `VerifiedFindings` veniva ancora assemblato a mano in più punti, soprattutto tra `MCPSharedState+CodeReviewReads` e `BugHunter`.

## Sintomo
Contatori, replay metadata e gate potevano divergere tra:
- `readCodeReviewStatus`
- `bughunter_status`
- payload secondari costruiti sopra gli stessi snapshot

## Impatto
Rischio di output incoerente tra entrypoint diversi pur leggendo la stessa source of truth.

## Gravità
Media

## Causa probabile
Lo status payload è cresciuto per tranche, quindi i campi shared sono stati aggiunti in punti diversi senza un service dedicato.

## Fix applicato
- aggiunto `VerifiedFindingsStatusService`
- `readCodeReviewStatus` ora delega al service shared
- `bughunter_status` legge il payload status dal service shared
- aggiunto test di regressione sul payload dello status
