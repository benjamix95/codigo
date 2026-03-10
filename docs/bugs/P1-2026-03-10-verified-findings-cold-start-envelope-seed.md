# P1 — Cold start del TaskActivityStore degrada l'envelope dei verified findings

## Bug Fix Record
- Categoria: A
- Bug: al primo ingest dopo un riavvio, `TaskActivityStore` ricostruiva i verified findings solo dallo snapshot, ignorando envelope/checkpoint già persistiti.
- Sintomo: metadata già salvati, come `commandLog` e versioning, sparivano durante il primo `ingestCodeReviewSnapshot(...)`.
- Impatto: rischio di downgrade dello stato persistito e di sovrascrittura di snapshot più ricchi con una versione ricostruita dal solo payload review.
- Gravità: alta
- Steps to reproduce:
  1. Persistire un `VerifiedFindingsSessionEnvelope` per una sessione review.
  2. Creare un nuovo `TaskActivityStore` vuoto.
  3. Ingerire uno snapshot della stessa sessione senza `verifiedFindings` embedded.
- Risultato attuale: lo store non caricava l'envelope persistito e risincronizzava da zero.
- Risultato atteso: lo store deve usare l'envelope persistito come seed della sync quando la cache in memoria è vuota.
- Causa probabile: `verifiedFindingsEnvelope(...)` leggeva solo cache in memoria e snapshot già presenti nello store, non la shared state persistita.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+VerifiedFindings.swift`
  - `Tests/SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests.swift`
- Non-scope:
  - cambi architetturali a `VerifiedFindingsSessionSyncService`
  - modifica del formato snapshot
- Moduli confinanti da verificare:
  - `TaskActivityStore+CodeReview.swift`
  - `PipelineIntegrationVerifiedFindingsTests`
- Test da aggiungere o aggiornare:
  - regressione sul cold start con envelope persistito e store appena creato
- Strategia di fix minimo:
  - estendere `verifiedFindingsEnvelope(...)` per recuperare envelope o rebuild persistiti quando cache e snapshot locali sono vuoti
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests`
- Commit previsto: `fix(review): seed verified findings sync from persisted envelope`

## Evidenza
- il test nuovo persiste un `commandLog`, istanzia uno store vuoto e verifica che il primo ingest preservi quel metadata invece di azzerarlo
