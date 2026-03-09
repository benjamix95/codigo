# P2 — La queue del lifecycle review/security era ancora duplicata negli handler MCP

## Categoria
Categoria B

## Bug
Gli handler MCP `review_*` e `security_*` continuavano a costruire manualmente ownership check, enqueue dei comandi e gating patch, invece di usare un service condiviso del core.

## Sintomo
La logica di queue per `verify/prepare/apply/revalidate/rollback/close` era distribuita tra handler MCP e helper locali, con rischio di divergenza tra review e security.

## Impatto
Maggiore rischio regressivo e minore aderenza al piano “una sola pipeline shared”.

## Gravità
Media

## Riproduzione
1. Leggere gli handler MCP `CodeReviewHandler+PatchWorkflow`.
2. Osservare che apply/queue/ownership erano assemblati localmente.
3. Confrontare con il wrapper `Security`, che riusava quegli handler ma non un service di lifecycle esplicito.

## Causa probabile
Il command path review è cresciuto prima del core `VerifiedFindings`, quindi il backend shared non aveva ancora un service applicativo dedicato al lifecycle.

## Fix applicato
- introdotto `VerifiedFindingsLifecycleCommandService`
- handler MCP review ora usano il service condiviso per queue e gating patch
- `BugHunter` autofix continua a riusare il workflow review, ma sopra una base più canonica

## Regressione da coprire
- queue di `revalidate/rollback/close`
- apply patch solo con artifact verificato
- filtro autofix `BugHunter` ancora verde dopo il refactor del lifecycle
