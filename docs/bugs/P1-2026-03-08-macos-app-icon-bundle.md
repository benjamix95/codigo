# P1 - macOS app icon non stabile fuori dal Dock

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: l'icona dell'app viene mostrata correttamente solo nel Dock, ma non come icona bundle stabile per notifiche, Stage Manager e altri punti del sistema.
- Sintomo: notifiche e Stage Manager non usano l'icona prevista oppure mostrano un'icona ridotta/non standard.
- Impatto: branding incoerente, identificazione app degradata e comportamento non conforme alle aspettative di macOS.
- Gravità: alta lato UX/macOS integration
- Steps to reproduce:
  1. Avviare l'app da eseguibile locale o da `Codigo.app`.
  2. Generare una notifica o osservare l'app in Stage Manager.
  3. Confrontare l'icona mostrata con quella vista nel Dock.
- Risultato attuale: il Dock può mostrare l'icona corretta grazie a un override runtime, mentre il sistema non dispone di una bundle icon stabile.
- Risultato atteso: tutte le superfici macOS devono usare la stessa icona bundle (`.icns`) dichiarata nel pacchetto applicazione.
- Causa probabile: combinazione di metadata bundle incompleti, asset icona degradati, firma bundle locale incoerente e assenza di `Assets.car` nel bundle principale. L'app impostava `applicationIconImage` a runtime da `AppLogo.png`, ma il bundle non dichiarava né installava correttamente un file icona `.icns`, mancava `CFBundleExecutable`, i PNG in `AppIcon.appiconset` non erano coerenti con il sorgente principale, il bundle rilanciato non veniva rifirmato dopo la copia delle risorse e Stage Manager/notifiche non trovavano un asset catalog compilato `AppIcon`.
- Scope consentito: `Info.plist`, packaging app macOS, installer icona bundle, test di regressione packaging.
- Non-scope: redesign grafico dell'icona, refactor UI, modifiche ai flussi notifiche.
- Moduli confinanti da verificare: bootstrap app, creazione `Codigo.app`, risoluzione risorse SwiftPM.
- Test da aggiungere o aggiornare: test su installazione icona bundle e dichiarazione `CFBundleIconFile`.
- Strategia di fix minimo: installare `Codigo.icns`, dichiararla nel plist, usarla nel packaging locale e rimuovere la dipendenza dall'override runtime del Dock.
- Verifica post-fix:
  1. `swift test --filter AppBundleIconInstallerTests`
  2. `./Scripts/build-app.sh`
  3. Verifica manuale di `Codigo.app/Contents/Resources/Codigo.icns`
  4. Smoke manuale su Dock, notifiche e Stage Manager
- Commit previsto: `fix(packaging): install stable macos app icon`
