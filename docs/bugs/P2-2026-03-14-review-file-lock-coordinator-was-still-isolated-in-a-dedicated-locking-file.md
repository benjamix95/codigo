# P2 — review file lock coordinator was still isolated in a dedicated locking file

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- Il dominio review manteneva ancora `FileLockCoordinator.swift` come file Swift non-UI isolato, anche se il coordinatore viene usato solo dal flusso review session/pipeline.

## Sintomo
- Il coordinatore dei lock viveva in una cartella separata rispetto allo state review che ne incapsula il ciclo di vita.

## Impatto
- Debito Swift legacy review più alto del necessario.
- Ownership del locking review dispersa.

## Gravità
- Media.

## Steps to reproduce
1. Aprire `Engine/CoderEngine/Sources/CodeReview/Locking`.
2. Verificare la presenza di `FileLockCoordinator.swift`.
3. Osservare che il tipo è consumato solo dal runtime review/session pipeline.

## Risultato attuale
- Il coordinatore dei lock era ancora un file residuale separato.

## Risultato atteso
- Il coordinatore deve vivere nel perimetro session-side review che già possiede stato e sincronizzazione.

## Causa probabile
- Il drain review ha rimosso prima bridge e servizi, lasciando il locking come residuo organizzativo.

## Scope consentito
- `CodeReviewSessionState.swift`
- `FileLockCoordinator.swift`
- test locking review correlati
- progetto Xcode
- docs cutover review

## Non-scope
- pipeline worker logic
- runtime Rust
- UI

## Moduli confinanti da verificare
- `FileLockCoordinatorTests`
- `ReviewPipelineCoordinatorTests`
- build `CoderEngineTests-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test necessario: esiste già copertura dedicata sul contratto del lock coordinator

## Strategia di fix minimo
- Spostare `FileLockCoordinator` in `CodeReviewSessionState.swift`.
- Eliminare il file locking dedicato dal target.
- Validare con build e subset locking.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `FileLockCoordinatorTests` e `ReviewPipelineCoordinatorTests`

## Commit previsto
- `refactor(review): fold file lock coordinator into session state`
