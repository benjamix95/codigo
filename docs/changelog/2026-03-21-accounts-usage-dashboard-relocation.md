# 2026-03-21 accounts usage dashboard relocation

## Summary
- spostato `AccountUsageDashboardStore` in `Services/UsageDashboard`
- nessuna modifica logica; solo riallineamento del perimetro supporto/presentazione

## Changes
- `App/SoloCodeApp/Sources/Services/UsageDashboard/AccountUsageDashboardStore.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornato il path del file spostato
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta allowlist per il dashboard store

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CLIAccountLoginCoordinatorTests -only-testing:SoloCodeAppTests/CLIProfileProvisionerTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Accounts/AccountUsageDashboardStore.swift,App/SoloCodeApp/Sources/Services/UsageDashboard/AccountUsageDashboardStore.swift,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
