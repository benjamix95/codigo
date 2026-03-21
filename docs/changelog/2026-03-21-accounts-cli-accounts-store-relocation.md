# 2026-03-21 accounts cli accounts store relocation

## Summary
- spostato `CLIAccountsStore*` in `Accounts/Support/Store`
- nessuna modifica logica; solo riallineamento del perimetro supporto/store

## Changes
- `App/SoloCodeApp/Sources/Accounts/Support/Store/CLIAccountsStore.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Store/CLIAccountsStore+Persistence.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CLIAccountLoginCoordinatorTests -only-testing:SoloCodeAppTests/CLIProfileProvisionerTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Accounts/Store/CLIAccountsStore.swift,App/SoloCodeApp/Sources/Accounts/Store/CLIAccountsStore+Persistence.swift,App/SoloCodeApp/Sources/Accounts/Support/Store/CLIAccountsStore.swift,App/SoloCodeApp/Sources/Accounts/Support/Store/CLIAccountsStore+Persistence.swift,Solo Code.xcodeproj/project.pbxproj'`
