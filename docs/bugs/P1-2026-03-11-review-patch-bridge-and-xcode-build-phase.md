# P1 — Il bridge patch Rust non era visibile all’app e il build phase Xcode del backend Rust degradava male

## Bug Fix Record
- Categoria: A
- Bug: l’app non riusciva a risolvere `ReviewPatchRustBridge` dal target `Solo Code`, e il build phase Rust Xcode poteva mostrare un errore rumoroso su `Cargo.toml` pur continuando la build.
- Sintomo: errore Swift `Cannot find 'ReviewPatchRustBridge' in scope` e messaggio shell `failed to read .../Native/RustCore/Cargo.toml`.
- Impatto: build locale rotta o confusa anche con codice corretto già presente nel repo.
- Gravita': alta lato esperienza di build.
- Steps to reproduce:
  1. Aprire `Solo Code.xcworkspace`.
  2. Compilare lo scheme `Solo Code-Debug`.
  3. Osservare l’errore sul simbolo patch bridge e il messaggio spurio del build phase Rust.
- Risultato attuale: `ReviewPatchRustBridge` deve essere visibile al target app e il build phase Rust deve uscire in modo pulito quando il crate non è leggibile nel sandbox Xcode.
- Risultato atteso: build `Solo Code-Debug` verde senza env speciali.
- Causa probabile: visibilità troppo stretta del bridge patch e controllo insufficiente nel build phase prima del `cargo build`.
- Scope consentito:
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/ReviewPatchRustBridge.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - UI
  - core Rust logic
- Moduli confinanti da verificare:
  - `VerifiedFindingsPatchExecutionService`
  - build scheme `Solo Code-Debug`
- Test da aggiungere o aggiornare:
  - build smoke dello scheme app
- Strategia di fix minimo:
  - rendere pubblico il bridge patch necessario al target app
  - aggiungere un check di leggibilità del crate nel build phase Xcode e silenziare il failure rumoroso
- Verifica post-fix:
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- Commit previsto: `fix(review): expose patch rust bridge to app target`
