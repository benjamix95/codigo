# 2026-03-08 - macOS app icon bundle fix

- Aggiunto `App/SoloCodeApp/Resources/Codigo.icns` come icona bundle macOS stabile.
- Aggiornato [Package.swift](/Users/benjaminstoica/codigo/Package.swift) per includere `Codigo.icns` tra le risorse del target.
- Aggiornato [Info.plist](/Users/benjaminstoica/codigo/App/SoloCodeApp/Sources/Info.plist) con `CFBundleIconFile = Codigo.icns`.
- Rifinito [Info.plist](/Users/benjaminstoica/codigo/App/SoloCodeApp/Sources/Info.plist) con `CFBundleExecutable = Codigo` e `CFBundleIconFile = Codigo` per aderire meglio ai metadata attesi da macOS.
- Aggiunto [AppBundleIconInstaller.swift](/Users/benjaminstoica/codigo/App/SoloCodeApp/Sources/App/Packaging/AppBundleIconInstaller.swift) per copiare l'icona nel bundle generato localmente.
- Aggiunto [AppBundleSigner.swift](/Users/benjaminstoica/codigo/App/SoloCodeApp/Sources/App/Packaging/AppBundleSigner.swift) per rifirmare ad-hoc il bundle locale dopo l'aggiornamento di plist e risorse.
- Aggiunto [AppAssetCatalogInstaller.swift](/Users/benjaminstoica/codigo/App/SoloCodeApp/Sources/App/Packaging/AppAssetCatalogInstaller.swift) per compilare `Assets.xcassets` in `Assets.car` e `AppIcon.icns` nel bundle principale.
- Aggiornato [AppDelegate.swift](/Users/benjaminstoica/codigo/App/SoloCodeApp/Sources/App/AppDelegate.swift) per installare l'icona nel bundle rilanciato e usare un fallback runtime dal file `.icns` per il Dock.
- Esteso [RuntimeResourceLocator.swift](/Users/benjaminstoica/codigo/App/SoloCodeApp/Sources/Utilities/RuntimeResourceLocator.swift) con il resolver dell'icona `.icns`.
- Aggiornato [Scripts/build-app.sh](/Users/benjaminstoica/codigo/Scripts/build-app.sh) per copiare `Codigo.icns` e i resource bundle SwiftPM dentro `Codigo.app`.
- Rigenerati i PNG in [AppIcon.appiconset](/Users/benjaminstoica/codigo/App/SoloCodeApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json) e [Codigo.icns](/Users/benjaminstoica/codigo/App/SoloCodeApp/Resources/Codigo.icns) dal sorgente principale.
- Esteso [AppBundleIconInstallerTests.swift](/Users/benjaminstoica/codigo/Tests/SoloCodeAppTests/AppBundleIconInstallerTests.swift) come copertura di regressione per sorgente icona, copia nel bundle, chiavi plist, argomenti `actool` e rappresentazioni standard della `.icns`.
