# P2 — review session registry suite remains red on unrelated Rust mutation paths

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- La suite `ReviewSessionRegistryTests` resta rossa sui path `dismissFinding`, `addComment` e `updateConfig` che dipendono dalla mutazione snapshot via Rust bridge.

## Sintomo
- I test che si aspettano mutazioni live del registry non aggiornano finding, config ed eventi.

## Impatto
- Le tranche session-side devono validare con subset più stretti per evitare falsi negativi.
- Esiste debito strutturale sui path di mutazione live review.

## Gravità
- Media.

## Steps to reproduce
1. Eseguire `xcodebuild test-without-building -only-testing:CoderEngineTests/ReviewSessionRegistryTests`.
2. Osservare failure su:
   - `testDismissFindingUsesRustMutationForLiveSession`
   - `testAddCommentUsesRustMutationForLiveSession`
   - `testUpdateConfigUsesRustMutationForLiveSession`

## Risultato attuale
- Le mutazioni via bridge Rust non producono gli effetti attesi nel registry test.

## Risultato atteso
- Il registry deve applicare finding/config/event updates coerenti alle risposte di mutazione.

## Causa probabile
- Debito preesistente sul boundary `review_core_command_mutate_snapshot` o sul suo wiring test-side.

## Scope consentito
- Nessun fix in questa tranche.
- Solo documentazione del rischio per non mascherare il problema.

## Non-scope
- Spostare o correggere il bridge Rust del registry in questa tranche

## Moduli confinanti da verificare
- `ReviewSessionRegistry`
- `CodeReviewSessionState`
- review core command mutation bridge

## Test da aggiungere o aggiornare
- futura regressione dedicata sui payload di mutazione live

## Strategia di fix minimo
- Rinviare a tranche separata perché il problema è strutturale e fuori scope rispetto al drain dei lifecycle models.

## Verifica post-fix
- Non applicabile in questa tranche.

## Commit previsto
- Nessuno in questa tranche; il bug viene solo registrato.
