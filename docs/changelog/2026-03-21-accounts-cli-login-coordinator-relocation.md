# 2026-03-21 accounts cli login coordinator relocation

## Summary
- spostato `CLIAccountLoginCoordinator*` in `Accounts/Support/Login`
- nessuna modifica di logica; solo riallineamento del perimetro supporto/dominio

## Changes
- `App/SoloCodeApp/Sources/Accounts/Support/Login/CLIAccountLoginCoordinator.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Login/CLIAccountLoginCoordinator+Commands.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Login/CLIAccountLoginCoordinator+Flow.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Login/CLIAccountLoginCoordinator+Parsing.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Login/CLIAccountLoginCoordinator+Session.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CLIAccountLoginCoordinatorTests -only-testing:SoloCodeAppTests/CLIProfileProvisionerTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Accounts/Login/CLIAccountLoginCoordinator.swift,App/SoloCodeApp/Sources/Accounts/Login/CLIAccountLoginCoordinator+Commands.swift,App/SoloCodeApp/Sources/Accounts/Login/CLIAccountLoginCoordinator+Flow.swift,App/SoloCodeApp/Sources/Accounts/Login/CLIAccountLoginCoordinator+Parsing.swift,App/SoloCodeApp/Sources/Accounts/Login/CLIAccountLoginCoordinator+Session.swift,App/SoloCodeApp/Sources/Accounts/Support/Login/CLIAccountLoginCoordinator.swift,App/SoloCodeApp/Sources/Accounts/Support/Login/CLIAccountLoginCoordinator+Commands.swift,App/SoloCodeApp/Sources/Accounts/Support/Login/CLIAccountLoginCoordinator+Flow.swift,App/SoloCodeApp/Sources/Accounts/Support/Login/CLIAccountLoginCoordinator+Parsing.swift,App/SoloCodeApp/Sources/Accounts/Support/Login/CLIAccountLoginCoordinator+Session.swift,Solo Code.xcodeproj/project.pbxproj'`
