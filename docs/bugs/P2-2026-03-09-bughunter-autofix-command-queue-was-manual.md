# P2 — La queue del lifecycle autofix BugHunter era ancora costruita manualmente nell'app

## Categoria
Categoria B

## Bug
Anche dopo l’introduzione dei workflow service shared, `CodigoApp+BugHunterExecution+Autofix` accodava ancora i comandi patch review tramite `enqueueCodeReviewCommand` diretto.

## Sintomo
Il path autofix applicativo non passava dal service lifecycle shared del core, quindi restava più fragile e meno coerente col resto del rollout.

## Impatto
Ultimo accoppiamento residuo tra `BugHunter` app execution e queue review raw.

## Gravità
Media

## Causa probabile
Il refactor verso il core shared è stato progressivo; il path autofix app è rimasto indietro rispetto agli handler MCP.

## Fix applicato
- `BugHunterWorkflowService` ora espone anche `queueLifecycleCommand`
- `CodigoApp+BugHunterExecution+Autofix` usa il workflow service shared per accodare il lifecycle patch
- aggiunto test di regressione dedicato
