# P1 — review patch workflow con validation opportunistica

## Sintomo
La pipeline patch review validava l'apply con un quality gate best-effort basato su `TestProjectDetector`, senza un profilo di validazione esplicito e senza report strutturato.

## Impatto
- patch marcate come verificate senza gate uniforme
- apply con semantica di successo piu' forte della garanzia reale
- impossibilita' di riusare lo stesso guard in commit, hook e CI

## Root cause probabile
Il workflow patch e' cresciuto attorno a `git apply --check` e a un test command generico, invece di passare da un orchestrator di validazione dedicato.

## Fix applicato
- introdotto il sottosistema `Validation` in `CoderEngine`
- `preparePatch` ora valida subito la patch preview
- `verifyPatch` richiede `validationStatus == passed`
- `applyPatch` esegue validazione post-apply con rollback su failure

## Regressione da coprire
- patch preview non deve diventare `verified` se validation fallisce
- patch apply deve fare rollback se la validazione post-apply fallisce
