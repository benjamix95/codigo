# P1 — Todo workflow: follow-up spuri, ordine non sequenziale e completed invisibili

Data: 2026-03-27
Stato: fixed
Area: Chat / Todo / Plan execution / Pipeline integration

## Sintesi

Il workflow todo mostrava regressioni che rendevano inaffidabile la checklist di esecuzione:

1. poteva comparire un solo todo `Code Review & Test` anche senza una vera checklist esecutiva;
2. i follow-up finali non erano governati da una sequenza unica (`Code Review & Test` non sempre in coda, `Doc Writer` assente);
3. l’auto-completion post-subagent poteva chiudere un review todo `pending` prima che fosse davvero il prossimo step;
4. il composer overlay spariva quando tutti i todo diventavano `done`, quindi i completed non restavano visibili con strikethrough.

## Priorità

- P1: degrada il flusso principale di esecuzione e la fiducia nello stato della checklist.

## Root cause

- Creazione del follow-up review in punti separati e non centralizzati (`finalizePlanBuild`, finalizzazione turni con code edits).
- Mancanza di una policy condivisa per i follow-up finali di esecuzione.
- Auto-completion batch che poteva promuovere/completare il review step fuori ordine.
- Policy UI overlay basata sulla presenza di almeno un todo non-completato, invece che sulla presenza di todo reali visibili.

## Fix applicato

- Introdotta `TodoExecutionFollowUpPolicy` per normalizzare i titoli di esecuzione e imporre il finale:
  - task reali
  - `Code Review & Test`
  - `Doc Writer`
- Rimossa la creazione runtime isolata del follow-up review in `PipelineIntegrationService.finalizePlanBuild`.
- Rimossa la creazione automatica di un review todo standalone in `ChatPanelView+PartR_Tail`.
- Aggiornata la logica di auto-completion per non chiudere il review step finché esiste lavoro esecutivo reale non completato.
- Aggiornata la visibilità del composer overlay per mantenere visibili i completed reali e continuare a nascondere i placeholder operativi.

## Verifica

- Test mirati eseguiti con successo su:
  - `TodoExecutionFollowUpPolicyTests`
  - `ComposerTodoOverlayStateTests`
  - `ChatPanelTodoFinalizationTests`
  - `PipelineIntegrationServiceTests`

## Rischi residui

- I flow runtime non-plan senza checklist esplicita non forzano automaticamente follow-up review/doc: scelta intenzionale per evitare todo spuri.
- Se in futuro si vorranno follow-up finali anche per runtime non-plan, servirà una policy dedicata con ordering esplicito.
