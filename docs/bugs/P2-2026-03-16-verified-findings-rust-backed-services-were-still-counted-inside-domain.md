# P2 - I servizi `VerifiedFindings` gia' Rust-backed erano ancora conteggiati nel dominio applicativo

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: cinque servizi `VerifiedFindings` che ormai agivano soprattutto come adapter del review core Rust restavano nel prefisso hard-fail `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`.
- Sintomo: dopo il batch precedente l'audit strict review-scope restava a `37` file legacy non-UI, di cui `13` nel dominio `VerifiedFindingsCore`.
- Impatto: il debito residuo del dominio `VerifiedFindingsCore` risultava gonfiato da file che non sono piu' ownership primaria di business logic ma host/replay/status/sync del review core Rust.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit strict review-scope dopo il batch `review-core-adapters-infrastructure-relocation`.
  2. Osservare `VerifiedFindingsSessionSyncService`, `VerifiedFindingsService` e `VerifiedFindingsStatusService` ancora nel prefisso hard-fail `VerifiedFindingsCore/Application`.
  3. Verificare che i relativi test coprano gia' i bridge Rust di sync/replay/projection.
- Risultato attuale:
  - i servizi Rust-backed sono ora sotto `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/VerifiedFindings/`
  - il prefisso hard-fail `VerifiedFindingsCore` conserva solo i file ancora realmente di dominio/business logic
- Risultato atteso: i servizi che orchestrano sync/replay/status del review core Rust devono vivere nell'infrastruttura review-core, non nel dominio applicativo `VerifiedFindingsCore`.
- Causa probabile: i batch precedenti avevano portato Rust nel comportamento ma non avevano ancora riallineato il layer fisico dei servizi `VerifiedFindings`.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSessionSyncService*`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsService.swift`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStatusService.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/VerifiedFindings/**`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - `VerifiedFindingsQueryService`
  - `VerifiedFindingsLifecycleCommandService`
  - `VerifiedFindingsCanonicalStore`
  - logica di business residua in `CodeReview`
- Moduli confinanti da verificare:
  - `VerifiedFindingsSessionSyncServiceTests`
  - `VerifiedFindingsServiceTests`
  - `VerifiedFindingsStatusServiceTests`
  - `VerifiedFindingsReplayServiceTests`
  - `VerifiedFindingsProjectionBuilderTests`
- Test da aggiungere o aggiornare:
  - nessun test nuovo; usare le regression suite esistenti per sync/replay/status/projection
- Strategia di fix minimo:
  - ricollocare i cinque servizi nel layer `Infrastructure/ReviewCore/VerifiedFindings`
  - aggiornare soltanto i path del progetto Xcode, senza cambiare il comportamento
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests -only-testing:CoderEngineTests/VerifiedFindingsServiceTests -only-testing:CoderEngineTests/VerifiedFindingsStatusServiceTests -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests -only-testing:CoderEngineTests/VerifiedFindingsProjectionBuilderTests`
  - audit strict review-scope
- Commit previsto: `fix(review): move verified findings rust services into infrastructure`

## Effetto osservato
- review strict prima del batch: `37` legacy non-UI
- review strict dopo il batch: `32` legacy non-UI
- riduzione per prefisso:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore`: da `13` a `8`
