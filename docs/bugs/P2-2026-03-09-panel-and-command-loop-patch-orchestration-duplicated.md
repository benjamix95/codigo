# P2 — Panel store e command loop avevano ancora due orchestrazioni patch separate

## Categoria
Categoria B

## Bug
Il panel `CodeReview` e il command loop dell’app usavano entrambi `ReviewPatchWorkflowService`, ma con orchestrazioni parallele e mutation snapshot duplicate.

## Sintomo
Il lifecycle patch `prepare/apply/revalidate/rollback/open_pr/merge_pr` viveva in due posti distinti:
- path command loop
- path panel store

## Impatto
Rischio di drift comportamentale tra UI e command path, nonostante agissero sugli stessi finding e patch artifact.

## Gravità
Media

## Causa probabile
Il workflow patch è nato lato review ed è stato poi riusato in più entrypoint senza un execution service app-level condiviso.

## Fix applicato
- introdotto `VerifiedFindingsPatchExecutionService`
- il command loop e il panel store usano ora lo stesso service condiviso
- spezzato il patch workflow del panel in file separati per restare sotto soglia

## Regressione da coprire
- mapping patch -> snapshot coerente
- apply patch da panel/command loop con stesso behaviour
