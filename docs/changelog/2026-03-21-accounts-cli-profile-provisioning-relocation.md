# 2026-03-21 accounts cli profile provisioning relocation

## Summary
- spostato il blocco `CLIProfileProvisioner*` in `Accounts/Support/Provisioning`
- nessuna modifica comportamentale; solo riallineamento del perimetro di ownership

## Changes
- `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+CodexConfigTemplate.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+CodexProfiles.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+InstructionsSync.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+Paths.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+ProviderProfiles.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+SelfHeal.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+Templates.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CLIProfileProvisionerTests -only-testing:SoloCodeAppTests/CLIProfileProvisionerInstructionSyncTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Accounts/Provisioning/CLIProfileProvisioner.swift,App/SoloCodeApp/Sources/Accounts/Provisioning/CLIProfileProvisioner+CodexConfigTemplate.swift,App/SoloCodeApp/Sources/Accounts/Provisioning/CLIProfileProvisioner+CodexProfiles.swift,App/SoloCodeApp/Sources/Accounts/Provisioning/CLIProfileProvisioner+InstructionsSync.swift,App/SoloCodeApp/Sources/Accounts/Provisioning/CLIProfileProvisioner+Paths.swift,App/SoloCodeApp/Sources/Accounts/Provisioning/CLIProfileProvisioner+ProviderProfiles.swift,App/SoloCodeApp/Sources/Accounts/Provisioning/CLIProfileProvisioner+SelfHeal.swift,App/SoloCodeApp/Sources/Accounts/Provisioning/CLIProfileProvisioner+Templates.swift,App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner.swift,App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+CodexConfigTemplate.swift,App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+CodexProfiles.swift,App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+InstructionsSync.swift,App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+Paths.swift,App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+ProviderProfiles.swift,App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+SelfHeal.swift,App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+Templates.swift,Solo Code.xcodeproj/project.pbxproj'`
