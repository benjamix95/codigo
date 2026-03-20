## 2026-03-20

- aggiunto un selettore targeted per `App/SoloCodeApp/Sources/Chat/Support/Providers/*` in [scripts/solocode-validate](/Users/benjaminstoica/SoloCode/scripts/solocode-validate)
- il validator ora esegue `ThreadProviderSelectionServiceTests` e `ProviderFactoryRuntimeParityTests` invece di ricadere sull'intera suite `SoloCodeAppTests`
- il fix serve a rendere committabile il tranche Rust della thread provider selection senza trascinare failure non correlate
