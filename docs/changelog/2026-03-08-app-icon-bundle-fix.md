# 2026-03-08 - macOS app icon bundle fix

- Aggiunto `App/SoloCodeApp/Resources/SoloCode.icns` come icona bundle macOS stabile.
- Aggiornato [Package.swift](/Users/benjaminstoica/SoloCode/Package.swift) per includere `SoloCode.icns` tra le risorse del target.
- Aggiornato [Info.plist](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Info.plist) con `CFBundleIconFile = SoloCode.icns`.
- Rifinito [Info.plist](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Info.plist) con `CFBundleExecutable = Solo Code` e `CFBundleIconFile = Solo Code` per aderire meglio ai metadata attesi da macOS.
- Aggiunto [AppBundleIconInstaller.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Packaging/AppBundleIconInstaller.swift) per copiare l'icona nel bundle generato localmente.
- Aggiunto [AppBundleSigner.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Packaging/AppBundleSigner.swift) per rifirmare ad-hoc il bundle locale dopo l'aggiornamento di plist e risorse.
- Aggiunto [AppAssetCatalogInstaller.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Packaging/AppAssetCatalogInstaller.swift) per compilare `Assets.xcassets` in `Assets.car` e `AppIcon.icns` nel bundle principale.
- Aggiornato [AppDelegate.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/AppDelegate.swift) per installare l'icona nel bundle rilanciato e usare un fallback runtime dal file `.icns` per il Dock.
- Esteso [RuntimeResourceLocator.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Utilities/RuntimeResourceLocator.swift) con il resolver dell'icona `.icns`.
- Aggiornato [Scripts/build-app.sh](/Users/benjaminstoica/SoloCode/Scripts/build-app.sh) per copiare `SoloCode.icns` e i resource bundle SwiftPM dentro `Solo Code.app`.
- Rigenerati i PNG in [AppIcon.appiconset](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json) e [SoloCode.icns](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Resources/SoloCode.icns) dal sorgente principale.
- Esteso [AppBundleIconInstallerTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/AppBundleIconInstallerTests.swift) come copertura di regressione per sorgente icona, copia nel bundle, chiavi plist, argomenti `actool` e rappresentazioni standard della `.icns`.
