# P2 — review session state suite remains red on unrelated coalescing and summary paths

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- La suite completa `CodeReviewSessionStateTests` resta rossa su path non toccati dalla tranche di consolidamento test.

## Sintomo
- Falliscono casi su coalescing e summary:
  - `testImmediateMilestoneCancelsPendingCoalescedEmission`
  - `testMarkAllOpenFindingsAsFixApplied`
  - `testSnapshotGroupedProperties`

## Impatto
- Le tranche test-side sul session state vanno validate con subset più stretti.

## Gravità
- Media.

## Steps to reproduce
1. Eseguire `xcodebuild test-without-building -only-testing:CoderEngineTests/CodeReviewSessionStateTests`.
2. Osservare le failure sui casi sopra.

## Risultato attuale
- La suite completa contiene failure strutturali non correlate al consolidamento dei file test.

## Risultato atteso
- Il session state test pack deve essere stabile anche su coalescing e grouped summaries.

## Causa probabile
- Debito preesistente nei path di emissione coalesced e nei criteri di summary/open-findings.

## Scope consentito
- Nessun fix runtime in questa tranche.
- Solo registrazione del rischio per non mascherare il problema.

## Non-scope
- Modificare il runtime session state in questa tranche

## Moduli confinanti da verificare
- `CodeReviewSessionState`
- `CodeReviewSessionSnapshot+Derived`
- emissione snapshot coalesced

## Test da aggiungere o aggiornare
- futura regressione separata sul contratto `patchApplied` / summary / coalescing

## Strategia di fix minimo
- Rinviare a tranche separata perché il problema è fuori scope rispetto al semplice drain test-side.

## Verifica post-fix
- Non applicabile in questa tranche.

## Commit previsto
- Nessuno specifico; il bug viene solo registrato.
