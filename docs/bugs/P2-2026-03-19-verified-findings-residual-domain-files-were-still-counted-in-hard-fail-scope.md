# P2 - I 3 file residui di VerifiedFindings erano ancora nel prefisso hard-fail del dominio

## Bug Fix Record
- Categoria: B
- Bug: dopo le tranche precedenti restavano ancora 3 file `VerifiedFindings` sotto `Engine/CoderEngine/Sources/VerifiedFindingsCore`, anche se ormai operavano come infrastruttura del review core e non come dominio applicativo isolato.
- Sintomo: l'audit strict review-scope riportava ancora `3` legacy non-UI nel prefisso `VerifiedFindingsCore`.
- Impatto: il backlog residuo veniva gonfiato da file ormai infrastrutturali, rallentando la misurazione corretta dell'ultimo tratto di migrazione.
- Gravità: P2
- Steps to reproduce:
  1. Eseguire `rust_cutover_guard` in review-scope strict.
  2. Osservare `Engine/CoderEngine/Sources/VerifiedFindingsCore: 3`.
  3. Verificare che i file residui sono `VerifiedFindingsLifecycleCommandService.swift`, `VerifiedFindingModels.swift`, `VerifiedFindingModels+PatchRun.swift`.
- Risultato attuale: i 3 file erano ancora conteggiati nel prefisso hard-fail `VerifiedFindingsCore`.
- Risultato atteso: questi file devono vivere nel layer `Infrastructure/ReviewCore/VerifiedFindings`, lasciando il prefisso `VerifiedFindingsCore` a zero.
- Causa probabile: le tranche precedenti avevano drenato i service principali ma avevano lasciato gli ultimi DTO/lifecycle file nel path storico.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsLifecycleCommandService.swift`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Domain/VerifiedFindingModels.swift`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Domain/VerifiedFindingModels+PatchRun.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/VerifiedFindings/**`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - refactor del motore `CodeReview`
  - porting a Rust delle session/pipeline Swift residue
  - UI del panel
- Moduli confinanti da verificare:
  - `VerifiedFindingsStartCommandServiceTests`
  - `VerifiedFindingsServiceTests`
  - `ReviewPatchWorkflowServiceTests`
- Test da aggiungere o aggiornare:
  - nessun test nuovo; smoke sulle suite che già compilano contro questi tipi/service
- Strategia di fix minimo:
  - ricollocare i 3 file sotto `Infrastructure/ReviewCore/VerifiedFindings/{Commands,Domain}`
  - aggiornare solo i path nel progetto Xcode
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsStartCommandServiceTests -only-testing:CoderEngineTests/VerifiedFindingsServiceTests`
  - audit strict review-scope
- Commit previsto: `chore(verified-findings): relocate residual files into review infrastructure`
