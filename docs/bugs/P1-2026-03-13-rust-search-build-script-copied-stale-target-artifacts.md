# P1 - `build_rust_search_backend.sh` copiava un artefatto Rust stale dal target sbagliato

## Bug Fix Record
- Categoria: A
- Bug: lo script `scripts/build_rust_search_backend.sh` cercava la dylib solo in `Native/RustCore/target/<profile>`, ma il workspace Cargo produce qui l'artefatto reale in `Native/target/<profile>`.
- Sintomo: dopo build Rust verde, `Native/RustCore/build/lib/libsolocode_rust_core.dylib` restava vecchio e senza i nuovi symbol FFI.
- Impatto: i test app e il runtime caricavano una dylib stale, facendo sembrare "non disponibile" il review core anche quando il codice nuovo era stato compilato.
- Gravita': alta, perche' rompe la validazione del boundary Swift -> Rust e rende fuorviante l'esito dei test panel.
- Steps to reproduce:
  1. Aggiungere un nuovo symbol FFI in `Native/RustCore`.
  2. Eseguire `./scripts/build_rust_search_backend.sh`.
  3. Verificare con `nm` che la dylib copiata in `Native/RustCore/build/lib` non contiene il nuovo symbol, mentre `Native/target/debug/libsolocode_rust_core.dylib` si'.
- Risultato attuale: lo script copiava il path crate-local stale e non il target workspace reale.
- Risultato atteso: lo script deve preferire `Native/target/<profile>` e usare il path crate-local solo come fallback.
- Causa probabile: il crate era stato inizialmente pensato fuori workspace; con il workspace Cargo attuale, il target di output effettivo e' cambiato.
- Scope consentito:
  - `scripts/build_rust_search_backend.sh`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - altri build script Rust non usati in questa tranche
- Moduli confinanti da verificare:
  - bootstrap test panel review
  - lookup symbol della dylib copiata
- Test da aggiungere o aggiornare:
  - verifica manuale `nm` sul file copiato
  - rilancio dei test panel che dipendono dai nuovi symbol FFI
- Strategia di fix minimo:
  - cercare l'artefatto in `Native/target/<profile>` prima del path crate-local
  - mantenere fallback al path legacy per compatibilita'
- Verifica post-fix:
  - `./scripts/build_rust_search_backend.sh`
  - `nm -gU Native/RustCore/build/lib/libsolocode_rust_core.dylib | rg 'review_core_panel_'`
  - test Xcode mirati sul panel review
- Commit previsto: `fix(build): copy rust review core from workspace target output`
