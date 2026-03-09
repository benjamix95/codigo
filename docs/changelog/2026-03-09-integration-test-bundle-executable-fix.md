# 2026-03-09 - Integration test bundle executable fix

- Corretta la configurazione effettiva del target integration in [Solo Code.xcodeproj/project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) collegando una sorgente reale alla `Sources` phase di `SoloCodeIntegrationTests`.
- Aggiunto uno smoke test host-based in [IntegrationHostSmokeTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeIntegrationTests/IntegrationHostSmokeTests.swift) per verificare caricamento bundle app e risoluzione delle risorse runtime principali.
- Aggiornata la documentazione del bug in [P1-2026-03-09-integration-test-bundle-missing-executable.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-09-integration-test-bundle-missing-executable.md) con causa confermata e strategia di fix.
- Validazione completata con successo tramite `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-IntegrationTests' -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
