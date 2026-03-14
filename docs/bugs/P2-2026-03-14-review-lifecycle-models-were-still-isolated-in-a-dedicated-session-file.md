# P2 — review lifecycle models were still isolated in a dedicated session file

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- Il perimetro `CodeReview/Session` manteneva ancora `ReviewLifecycleModels.swift` come file residuale dedicato a candidate, patch e outcome, separato dai file che usano davvero quei tipi.

## Sintomo
- I model type di candidate e patch erano lontani dalle factory e dallo state session che li manipola.
- `ReviewSessionOutcome` era separato dallo snapshot che lo espone e lo serializza.

## Impatto
- Debito Swift legacy review più alto del necessario.
- Ownership del lifecycle session più dispersa.

## Gravità
- Media.

## Steps to reproduce
1. Aprire `Engine/CoderEngine/Sources/CodeReview/Session`.
2. Verificare la presenza di `ReviewLifecycleModels.swift`.
3. Osservare che candidate, patch e outcome sono usati altrove ma vivono in un file dedicato residuale.

## Risultato attuale
- I tipi lifecycle erano ancora isolati in un file Swift non-UI separato.

## Risultato atteso
- I tipi devono stare nei file che li costruiscono e li mutano, riducendo frammentazione e debito legacy.

## Causa probabile
- Il drenaggio per tranche ha rimosso prima bridge e servizi, lasciando i model lifecycle come residuo organizzativo.

## Scope consentito
- `CodeReviewFinding+Factories.swift`
- `CodeReviewSessionState+CandidatesAndPatches.swift`
- `CodeReviewSessionSnapshot+Derived.swift`
- `ReviewLifecycleModels.swift`
- test session review correlati
- progetto Xcode
- docs cutover review

## Non-scope
- pipeline review
- review core Rust
- panel UI

## Moduli confinanti da verificare
- `CodeReviewFindingTests`
- `ReviewSessionRegistryTests`
- build `CoderEngineTests-Debug`
- boundary guard review

## Test da aggiungere o aggiornare
- regressione su `buildOutcomeSummary()` che conti patch state, PR aperte, conflitti e manual action

## Strategia di fix minimo
- Spostare `ReviewCandidate` e relativi enum nel file factory finding.
- Spostare `ReviewPatchArtifact` e relativi enum nel file state candidati/patch.
- Spostare `ReviewSessionOutcome` nello snapshot derived.
- Eliminare il file lifecycle dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `CodeReviewFindingTests` e `ReviewSessionRegistryTests`

## Commit previsto
- `refactor(review): fold lifecycle models into session modules`
