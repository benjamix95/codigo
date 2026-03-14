# P2 — verified finding enums were still isolated in a dedicated domain file

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- Il dominio `VerifiedFindingsCore` manteneva ancora `VerifiedFindingEnums.swift` come file Swift separato contenente solo enum già usati dai model file `VerifiedFindingModels.swift` e `VerifiedFindingModels+PatchRun.swift`.

## Sintomo
- Gli enum di finding, evidence, verification, patch e run erano lontani dai rispettivi model type che li usano.

## Impatto
- Debito Swift legacy review più alto del necessario.
- Ownership del dominio verified findings meno leggibile.

## Gravità
- Media.

## Steps to reproduce
1. Aprire `Engine/CoderEngine/Sources/VerifiedFindingsCore/Domain`.
2. Verificare la presenza di `VerifiedFindingEnums.swift`.
3. Osservare che il file contiene solo enum condivisi da due file modello già esistenti.

## Risultato attuale
- Gli enum di dominio vivevano in un file separato residuale.

## Risultato atteso
- Gli enum devono vivere vicino ai model type che serializzano e usano quel contratto.

## Causa probabile
- Il cutover per tranche aveva drenato prima servizi e bridge, lasciando questo file dominio come residuo organizzativo.

## Scope consentito
- `VerifiedFindingModels.swift`
- `VerifiedFindingModels+PatchRun.swift`
- `VerifiedFindingEnums.swift`
- test verified findings correlati
- progetto Xcode
- docs cutover review

## Non-scope
- servizi application
- projection builder
- panel UI

## Moduli confinanti da verificare
- `VerifiedFindingsServiceTests`
- `VerifiedFindingsStatusServiceTests`
- build `CoderEngineTests-Debug`
- boundary guard review

## Test da aggiungere o aggiornare
- regressione codable che tocchi insieme finding enums e run enums

## Strategia di fix minimo
- Spostare gli enum finding/evidence/verification nel file `VerifiedFindingModels.swift`.
- Spostare gli enum patch/run nel file `VerifiedFindingModels+PatchRun.swift`.
- Eliminare il file enum dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `VerifiedFindingsServiceTests` e `VerifiedFindingsStatusServiceTests`

## Commit previsto
- `refactor(review): fold verified finding enums into domain models`
