# P2 - Il security gate service restava isolato in un file application dedicato

## Bug Fix Record
- Categoria: B
- Bug: `VerifiedFindingsSecurityGateService.swift` restava un file Swift non-UI separato pur contenendo solo il gate security dei verified findings.
- Sintomo: il dominio `VerifiedFindingsCore` manteneva un file legacy dedicato con logica già coerente con `SecurityWorkflowService`.
- Impatto: backlog Swift non-UI più alto e frammentazione inutile del workflow security.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSecurityGateService.swift`.
  2. Verificare che il file contenga solo report, bridge request/response e `evaluate(...)`.
  3. Notare che il file compare ancora nel backlog review di `VerifiedFindingsCore`.
- Risultato attuale: il gate security viveva in un file separato.
- Risultato atteso: il gate security deve stare in `SecurityWorkflowService.swift`, accanto agli altri entrypoint security.
- Causa probabile: tranche precedenti avevano drenato helper verified findings più urgenti lasciando questo service residuale separato.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application`
  - `Tests/CoderEngineTests/VerifiedFindings`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - panel UI
  - persistence
  - MCP handlers
- Moduli confinanti da verificare:
  - `VerifiedFindingsSecurityGateServiceTests`
  - `SecurityWorkflowService`
- Test da aggiungere o aggiornare:
  - nessun nuovo test; aggiunto solo shim di compatibilità per preservare il nome pubblico cercato dalla suite
- Strategia di fix minimo:
  - spostare report e logica `evaluate(...)` in `SecurityWorkflowService.swift`
  - lasciare un shim `VerifiedFindingsSecurityGateService` nello stesso file per compatibilità
  - rimuovere il file dedicato e i riferimenti Xcode
- Verifica post-fix:
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/SecurityWorkflowService.swift,Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSecurityGateService.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
  - `./scripts/bootstrap_test_bundles.sh`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/VerifiedFindingsSecurityGateServiceTests`
- Commit previsto: `refactor(review): fold security gate into security workflow`

## Fix applicato
- `VerifiedFindingsSecurityGateReport`, bridge request/response e la logica `evaluate(...)` sono stati spostati in `SecurityWorkflowService.swift`
- aggiunto uno shim `VerifiedFindingsSecurityGateService` nello stesso file per preservare il contratto pubblico dei test
- rimosso `VerifiedFindingsSecurityGateService.swift` dal filesystem e dal progetto Xcode

## Esito
- `VerifiedFindingsCore` riduce di una unita' il conteggio Swift legacy non-UI
- nessun cambiamento comportamentale previsto
