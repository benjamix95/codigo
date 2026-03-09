# P2 — Panel store e command loop avevano ancora due orchestrazioni patch separate

## Categoria
Categoria B

## Bug
Il panel `CodeReview` e il command loop dell’app usavano entrambi `ReviewPatchWorkflowService`, ma con orchestrazioni parallele e snapshot mutation duplicate.

## Sintomo
Prepare/apply/revalidate/rollback/open_pr/merge_pr seguivano due flow diversi:
- uno nel command loop
- uno nel panel store

## Impatto
Rischio di drift comportamentale e regressioni diverse tra UI e command path, pur agendo sugli stessi finding e patch artifact.

## Gravità
Media

## Causa probabile
Il workflow patch era nato in una fase review-centric e poi riusato progressivamente, senza un service applicativo condiviso a livello app.

## Fix applicato
- introdotto `VerifiedFindingsPatchExecutionService`
- il command loop e il panel store ora riusano lo stesso service per l’orchestrazione patch
- spezzato il panel patch workflow in file separati per restare sotto soglia

## Regressione da coprire
- apply patch da panel e command loop con mapping patch/finding coerente
- upsert patch artifact aggiorna stato finding e outcome summary
