# P1 - La dylib del review core Rust non veniva pacchettizzata nel bundle macOS

## Bug Fix Record
- Categoria: A
- Bug: l’app macOS lanciata normalmente non trovava `libsolocode_rust_core.dylib`, quindi il `CodeReviewPanel` mostrava `library_missing` anche dopo il fix fail-closed del Git context.
- Sintomo: UI del panel review con errore `Runtime Rust review core non disponibile. Motivo: library_missing`.
- Impatto: il review core Rust risultava disponibile nei test forzati via env, ma indisponibile nell’app reale.
- Gravità: P1
- Steps to reproduce:
  1. Costruire o lanciare l’app da Xcode.
  2. Aprire il `CodeReviewPanel` e il picker commit/branch.
  3. Osservare il messaggio `library_missing`.
  4. Verificare che `Solo Code.app` non contenga `Contents/MacOS/solocode_rust/libsolocode_rust_core.dylib`.
- Risultato attuale: il target app copiava gli helper MCP nel bundle, ma non il review core Rust.
- Risultato atteso: la dylib `libsolocode_rust_core.dylib` deve essere costruita e copiata nel bundle app durante la build.
- Causa probabile: `build_rust_search_backend.sh` non veniva eseguito dal target app; i path di fallback del loader puntavano al repo o a prodotti esterni, non al contenuto del bundle.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing`
  - `scripts/build_rust_search_backend.sh`
  - `scripts/build-app.sh`
  - `scripts/run-app.sh`
  - `scripts/generate_xcode_project.rb`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `docs/bugs`, `docs/changelog`
- Non-scope:
  - runtime Rust del panel review
  - fallback Swift
  - servizi Git classici
- Moduli confinanti da verificare:
  - `ReviewCoreBridge.loadedState()`
  - packaging del bundle `.app`
  - script di build/lancio locali
- Test da aggiungere o aggiornare:
  - verifica manuale del bundle prodotto
  - build macOS con esecuzione della shell phase `Build Rust Review Core`
- Strategia di fix minimo:
  - copiare la dylib nel bundle app sotto `Contents/MacOS/solocode_rust`
  - estendere il loader Swift per cercare anche dentro il bundle
  - sincronizzare generator script e `.pbxproj` corrente
- Verifica post-fix:
  - `xcodebuild build -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination "platform=macOS"`
  - `find "…/Solo Code.app" -path '*solocode_rust*'`
  - `nm -gU "…/libsolocode_rust_core.dylib" | rg 'review_core_panel_git_context|review_core_version'`
- Commit previsto: `fix(build): bundle rust review core into macos app`

## Esito
- aggiunta build phase `Build Rust Review Core` al target app
- la dylib viene ora copiata nel bundle macOS
- il loader Swift cerca anche nei path bundle-internal coerenti con il packaging
