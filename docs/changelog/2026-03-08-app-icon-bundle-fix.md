# 2026-03-08 - macOS app icon bundle fix

- Aggiunto `Sources/CoderIDE/Resources/Codigo.icns` come icona bundle macOS stabile.
- Aggiornato [Package.swift](/Users/benjaminstoica/codigo/Package.swift) per includere `Codigo.icns` tra le risorse del target.
- Aggiornato [Info.plist](/Users/benjaminstoica/codigo/Sources/CoderIDE/Info.plist) con `CFBundleIconFile = Codigo.icns`.
- Aggiunto [AppBundleIconInstaller.swift](/Users/benjaminstoica/codigo/Sources/CoderIDE/Modules/App/Packaging/AppBundleIconInstaller.swift) per copiare l'icona nel bundle generato localmente.
- Aggiornato [AppDelegate.swift](/Users/benjaminstoica/codigo/Sources/CoderIDE/Modules/App/AppDelegate.swift) per installare l'icona nel bundle rilanciato e rimuovere l'override runtime dell'icona Dock.
- Esteso [RuntimeResourceLocator.swift](/Users/benjaminstoica/codigo/Sources/CoderIDE/Modules/Utilities/RuntimeResourceLocator.swift) con il resolver dell'icona `.icns`.
- Aggiornato [build-app.sh](/Users/benjaminstoica/codigo/build-app.sh) per copiare `Codigo.icns` e i resource bundle SwiftPM dentro `Codigo.app`.
- Aggiunto [AppBundleIconInstallerTests.swift](/Users/benjaminstoica/codigo/Tests/CoderIDETests/AppBundleIconInstallerTests.swift) come copertura di regressione per sorgente icona, copia nel bundle e chiave plist.
