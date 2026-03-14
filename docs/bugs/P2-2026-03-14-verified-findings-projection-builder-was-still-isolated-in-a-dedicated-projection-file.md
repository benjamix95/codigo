# P2 — verified findings projection builder was still isolated in a dedicated projection file

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- Il dominio `VerifiedFindingsCore` manteneva ancora `VerifiedFindingsProjectionBuilder.swift` come file Swift residuale dedicato a tipi projection e builder.

## Sintomo
- I tipi projection vivevano separati dallo snapshot canonical che li alimenta e dal servizio status che li espone.

## Impatto
- Debito Swift legacy review più alto del necessario.
- Ownership del flusso canonical -> projection più dispersa.

## Gravità
- Media.

## Steps to reproduce
1. Aprire `Engine/CoderEngine/Sources/VerifiedFindingsCore/Projection`.
2. Verificare la presenza di `VerifiedFindingsProjectionBuilder.swift`.
3. Osservare che il file contiene solo tipi projection e builder richiamati da servizi application.

## Risultato attuale
- Builder e tipi projection restavano in un file separato residuale.

## Risultato atteso
- I tipi projection devono stare vicino allo snapshot canonical e il builder vicino al servizio che lo usa.

## Causa probabile
- Le tranche precedenti hanno drenato prima servizi e bridge, lasciando il builder projection come residuo.

## Scope consentito
- `VerifiedFindingsCanonicalStore.swift`
- `VerifiedFindingsStatusService.swift`
- `VerifiedFindingsProjectionBuilder.swift`
- test verified findings correlati
- progetto Xcode
- docs cutover review

## Non-scope
- servizi bug hunter
- panel UI
- runtime Rust oltre il bridge già esistente

## Moduli confinanti da verificare
- `VerifiedFindingsProjectionBuilderTests`
- `VerifiedFindingsServiceTests`
- `VerifiedFindingsStatusServiceTests`
- build `CoderEngineTests-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test necessario: il perimetro ha già suite dedicate sulla projection

## Strategia di fix minimo
- Spostare i tipi projection nello store canonical.
- Spostare il builder e il bridge request/response nel servizio status.
- Eliminare il file projection dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `VerifiedFindingsProjectionBuilderTests`, `VerifiedFindingsServiceTests` e `VerifiedFindingsStatusServiceTests`

## Commit previsto
- `refactor(review): fold projection builder into verified services`
