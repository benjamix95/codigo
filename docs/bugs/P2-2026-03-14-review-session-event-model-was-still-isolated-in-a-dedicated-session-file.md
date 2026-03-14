# P2 — review session event model was still isolated in a dedicated session file

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- Il perimetro `CodeReview/Session` manteneva ancora `CodeReviewSessionEvent.swift` come file residuale dedicato al modello evento review.

## Sintomo
- Il tipo evento, le factory e la serializzazione vivevano separati dai moduli session che li emettono e li serializzano.

## Impatto
- Debito Swift legacy review più alto del necessario.
- Ownership del contratto evento dispersa.

## Gravità
- Media.

## Steps to reproduce
1. Aprire `Engine/CoderEngine/Sources/CodeReview/Session`.
2. Verificare la presenza di `CodeReviewSessionEvent.swift`.
3. Osservare che il file contiene solo tipo evento, enum e helper usati dal lifecycle review.

## Risultato attuale
- Il contratto evento restava in un file separato residuale.

## Risultato atteso
- Il tipo evento deve vivere accanto ai model factory e il relativo enum/factory vicino al lifecycle che lo emette.

## Causa probabile
- Il drenaggio review ha lasciato il contratto evento come residuo dopo la rimozione di altri wrapper session-side.

## Scope consentito
- `CodeReviewFinding+Factories.swift`
- `CodeReviewSessionState+Lifecycle.swift`
- `CodeReviewSessionEvent.swift`
- test session review correlati
- progetto Xcode
- docs cutover review

## Non-scope
- pipeline review
- runtime Rust
- panel UI

## Moduli confinanti da verificare
- `CodeReviewFindingTests`
- `MCPSharedCodeReviewSnapshotStoreTests`
- build `CoderEngineTests-Debug`

## Test da aggiungere o aggiornare
- regressione sul payload serializzato dell’evento review

## Strategia di fix minimo
- Spostare `CodeReviewSessionEvent` e `toPayload()` vicino ai model factory.
- Spostare `EventType` e le factory evento nel lifecycle session.
- Eliminare il file evento dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `CodeReviewFindingTests` e `MCPSharedCodeReviewSnapshotStoreTests`

## Commit previsto
- `refactor(review): fold session event model into session modules`
