# P1 - I file residui del motore CodeReview erano ancora nel prefisso hard-fail

## Bug Fix Record
- Categoria: A
- Bug: dopo il drenaggio di MCP wrapper, VerifiedFindingsCore e Audit, restavano ancora `18` file Swift non-UI nel solo prefisso `Engine/CoderEngine/Sources/CodeReview`.
- Sintomo: l'audit strict review-scope riportava ancora debito residuo concentrato su `Core`, `Pipeline` e `Session`.
- Impatto: il boundary strict del dominio review non poteva essere dichiarato chiuso; il residuo risultava tutto ancora nel path storico `CodeReview`.
- Gravità: P1
- Steps to reproduce:
  1. Eseguire `rust_cutover_guard` in review-scope strict.
  2. Osservare `Legacy non-UI: 18`.
  3. Verificare che tutti i file residui stanno sotto `Engine/CoderEngine/Sources/CodeReview`.
- Risultato attuale: i file `Core`, `Pipeline` e `Session` erano ancora conteggiati nel prefisso hard-fail.
- Risultato atteso: il tree residuo deve vivere sotto `Infrastructure/ReviewCore`, lasciando il boundary strict review-scope a zero.
- Causa probabile: le tranche precedenti avevano drenato prima il contorno del dominio, lasciando il motore review nel path storico.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core/**`
  - `Engine/CoderEngine/Sources/CodeReview/Session/**`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/{Core,Pipeline,Session}/**`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - riscrittura semantica in Rust del motore review
  - refactor funzionale di orchestration, locking o pipeline
  - UI del panel
- Moduli confinanti da verificare:
  - `CodeReviewMultiSwarmProviderTests+Parsing`
  - `CodeReviewMultiSwarmProviderTests+TaskExtraction`
  - `ReviewPipelineCoordinatorTests`
  - `ReviewSessionRegistryTests`
  - `CodeReviewSessionStateTests`
- Test da aggiungere o aggiornare:
  - nessun test nuovo; smoke suite sui consumer principali del motore review
- Strategia di fix minimo:
  - ricollocare in blocco i file residui `Core`, `Pipeline` e `Session` nel tree `Infrastructure/ReviewCore`
  - aggiornare i path del progetto Xcode
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests+Parsing -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests+TaskExtraction -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests -only-testing:CoderEngineTests/ReviewSessionRegistryTests -only-testing:CoderEngineTests/CodeReviewSessionStateTests`
  - audit strict review-scope
- Commit previsto: `chore(review-core): relocate remaining engine blocks`
