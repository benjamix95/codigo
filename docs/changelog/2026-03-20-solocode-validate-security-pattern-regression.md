## 2026-03-20

- corretto il regex del gate `security` in [scripts/solocode-validate](/Users/benjaminstoica/SoloCode/scripts/solocode-validate) per rilevare marker reali (`-----BEGIN PRIVATE KEY-----`, `token =`, `password =`) senza auto-matchare il pattern letterale del validator
- incluso il dominio `Accounts` nel passo `security` del validator, cosi' la tranche `accounts/providers` non salta i controlli su auth, network ed external command boundaries
- aggiunta regressione Rust in [solocode_validate_security_scan.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreRust/tests/solocode_validate_security_scan.rs)
- validazione usata per sbloccare la tranche `accounts/providers` del cutover totale a Rust
