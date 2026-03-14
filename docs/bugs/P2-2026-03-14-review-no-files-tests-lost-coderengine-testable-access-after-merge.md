# P2 — I test `ReviewPipelineNoFilesMessageTests` hanno perso l’accesso `@testable` a CoderEngine dopo il merge

## Categoria
- B — Importante ma non bloccante

## Bug
- Dopo il consolidamento dei test no-files in `CodeReviewPanelLiveRunExecutionTests.swift`, il target `SoloCodeAppTests` non compilava più.

## Sintomo
- Build failure su `ReviewPipelineCoordinator.noFilesAgainstRefMessage(...)` con errore di protezione `internal`.

## Impatto
- Il target `SoloCodeAppTests` non completava `build-for-testing`.
- I test di regressione del panel review non potevano più essere eseguiti.

## Gravità
- Media: regressione di build nel layer test.

## Steps to reproduce
1. Eseguire `xcodebuild build-for-testing -scheme "Solo Code-Debug"`.
2. Compilare `Tests/SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests.swift`.

## Risultato attuale
- Il compilatore rifiuta l’accesso a `noFilesAgainstRefMessage`.

## Risultato atteso
- Il test target deve poter leggere la API `internal` del modulo `CoderEngine`.

## Causa probabile
- Il file consolidato importava `CoderEngine` senza `@testable`, a differenza del perimetro originario dei test engine.

## Scope consentito
- `Tests/SoloCodeAppTests/CodeReviewPanelLiveRunExecutionTests.swift`

## Non-scope
- Visibilità pubblica dell’API engine
- Ristrutturazione dei messaggi no-files

## Moduli confinanti da verificare
- `ReviewPipelineNoFilesMessageTests`

## Test di regressione
- `SoloCodeAppTests/ReviewPipelineNoFilesMessageTests`

## Strategia di fix minimo
- Convertire l’import del modulo engine in `@testable import CoderEngine` nel file consolidato.

## Verifica post-fix
- `build-for-testing` verde.
- `ReviewPipelineNoFilesMessageTests` verdi.

## Commit previsto
- incluso nel fix dedicato del blocco review live mutations
