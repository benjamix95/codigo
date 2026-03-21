# 2026-03-21 accounts cli auth detector relocation

## Summary
- spostato `CLIAccountAuthDetector*` in `Accounts/Support/Authentication`
- nessuna modifica di logica; solo riallineamento del perimetro supporto/dominio

## Changes
- `App/SoloCodeApp/Sources/Accounts/Support/Authentication/CLIAccountAuthDetector.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Authentication/CLIAccountAuthDetector+Detection.swift`
- `App/SoloCodeApp/Sources/Accounts/Support/Authentication/CLIAccountAuthDetector+Identity.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CLIAccountAuthDetectorTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Accounts/Authentication/CLIAccountAuthDetector.swift,App/SoloCodeApp/Sources/Accounts/Authentication/CLIAccountAuthDetector+Detection.swift,App/SoloCodeApp/Sources/Accounts/Authentication/CLIAccountAuthDetector+Identity.swift,App/SoloCodeApp/Sources/Accounts/Support/Authentication/CLIAccountAuthDetector.swift,App/SoloCodeApp/Sources/Accounts/Support/Authentication/CLIAccountAuthDetector+Detection.swift,App/SoloCodeApp/Sources/Accounts/Support/Authentication/CLIAccountAuthDetector+Identity.swift,Solo Code.xcodeproj/project.pbxproj'`
