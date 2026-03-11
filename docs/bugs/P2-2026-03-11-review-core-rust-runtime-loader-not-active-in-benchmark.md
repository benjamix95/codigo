# P2 — Il benchmark post non conferma ancora il caricamento runtime del review core Rust

## Bug Fix Record
- Categoria: B
- Bug: il report `review-core-tranche1-post-engine.json` continua a segnare `rust_review_core_loaded=false` anche con `.dylib` buildata e path esplicito.
- Sintomo: il benchmark `post` misura ancora il fallback Swift per `verify_candidates` e `sync_verified_findings`.
- Impatto: la pipeline benchmark e' pronta, ma il delta prestazionale del percorso Rust non e' ancora dimostrato end-to-end nel runner test.
- Gravita': media
- Steps to reproduce:
  1. Costruire `Native/RustCore/build/lib/libsolocode_rust_core.dylib`.
  2. Eseguire `scripts/benchmark_review_pipeline_pre_post.sh --phase post --tag review-core-tranche1`.
  3. Controllare il campo `rust_review_core_loaded`.
- Risultato attuale: la `.dylib` esiste e contiene i simboli `review_core_*`, ma il benchmark post non osserva il bridge come attivo.
- Risultato atteso: il benchmark post deve caricare il backend Rust e riportarlo esplicitamente.
- Causa probabile: mismatch tra ambiente del test runner, `dlopen`, current working directory e bootstrap del loader condiviso.
- Scope consentito:
  - `RustSearchFFIClient.swift`
  - script benchmark review-core
  - eventuale logging diagnostico del loader
- Non-scope:
  - refactor del boundary FFI
  - rimozione del fallback Swift
- Moduli confinanti da verificare:
  - `ReviewCoreBridge`
  - `RustSearchFFIClient`
  - benchmark `ValidationPerformanceTests`
- Test da aggiungere o aggiornare:
  - smoke test esplicito sul loader review-core con path `.dylib` forzato
- Strategia di fix minimo:
  - aggiungere diagnostica del `dlopen`/symbol resolution e stabilizzare il path di bootstrap nei test
- Verifica post-fix:
  - benchmark `post` con `rust_review_core_loaded=true`
- Commit previsto: `test(review): add runtime loader diagnostics for rust review core`
