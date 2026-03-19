# P2 - I servizi command/query/security di `VerifiedFindings` erano ancora conteggiati nel dominio applicativo

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: cinque file `VerifiedFindings` gia' usati soprattutto come adapter/orchestratori del review core Rust restavano ancora nel prefisso hard-fail `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`.
- Sintomo: dopo il batch precedente l'audit strict review-scope restava a `32` file legacy non-UI, di cui `8` in `VerifiedFindingsCore`.
- Impatto: il dominio `VerifiedFindingsCore` continuava a sembrare piu' “applicativo” del reale, rallentando il drenaggio del debito review verso la sola logica ancora davvero non migrata.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit strict review-scope dopo il batch `verified-findings-rust-services-infrastructure-relocation`.
  2. Osservare ancora nel prefisso hard-fail file come `VerifiedFindingsCanonicalStore.swift`, `VerifiedFindingsStartCommandService.swift`, `VerifiedFindingsQueryService.swift`, `SecurityWorkflowService.swift` e `BugHunterAutofixSelectionService.swift`.
  3. Verificare che i test esistenti li esercitino gia' come adapter/orchestratori, non come UI o ownership di dominio puro.
- Risultato attuale:
  - i cinque file sono ora sotto `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/VerifiedFindings/`
  - il prefisso hard-fail `VerifiedFindingsCore` resta con soli `3` file legacy residui
- Risultato atteso: command/query/security adapter e store canonico legati al review core Rust devono vivere nell'infrastruttura review-core, non nel subtree applicativo `VerifiedFindingsCore`.
- Causa probabile: il cutover funzionale a Rust era gia' avanzato, ma il riallineamento fisico dei file era rimasto indietro di alcune tranche.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsCanonicalStore.swift`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsStartCommandService.swift`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsQueryService.swift`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/SecurityWorkflowService.swift`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/BugHunterAutofixSelectionService.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/VerifiedFindings/**`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - `VerifiedFindingsLifecycleCommandService.swift` perche' supera il limite dimensionale e richiede split dedicato
  - `VerifiedFindingModels.swift` e `VerifiedFindingModels+PatchRun.swift`
  - logica residua in `CodeReview`
- Moduli confinanti da verificare:
  - `VerifiedFindingsStartCommandServiceTests`
  - `VerifiedFindingsCommandCoordinatorTests`
  - `VerifiedFindingsSecurityGateServiceTests`
  - `VerifiedFindingsQueryServiceTests`
  - `BugHunterWorkflowServiceTests`
  - `BugHunterAutofixFilterTests`
- Test da aggiungere o aggiornare:
  - nessun test nuovo; usare le regression suite esistenti per command/query/security/bughunter
- Strategia di fix minimo:
  - ricollocare i cinque adapter nel layer `Infrastructure/ReviewCore/VerifiedFindings`
  - aggiornare solo i path di progetto Xcode
  - lasciare fuori il file a 301 righe per una tranche separata con split vero
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:CoderEngineTests/VerifiedFindingsCommandCoordinatorTests -only-testing:CoderEngineTests/VerifiedFindingsSecurityGateServiceTests -only-testing:CoderEngineTests/VerifiedFindingsQueryServiceTests -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests+TaskExtraction -only-testing:CoderEngineTests/BugHunterAutofixFilterTests`
  - audit strict review-scope
- Commit previsto: `fix(review): move verified findings adapters into infrastructure`

## Effetto osservato
- review strict prima del batch: `32` legacy non-UI
- review strict dopo il batch: `27` legacy non-UI
- riduzione per prefisso:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore`: da `8` a `3`
