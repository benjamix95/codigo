# P1 - Il bootstrap dei test bundle falliva per `pipefail` e `return` implicito

## Bug Fix Record
- Categoria: A
- Bug: [bootstrap_test_bundles.sh](/Users/benjaminstoica/SoloCode/scripts/bootstrap_test_bundles.sh) falliva durante `solocode-validate` anche quando i bundle di test erano corretti e firmabili.
- Sintomo:
  - `solocode-validate` cadeva su `testBootstrap`
  - lo script usciva con `141` o con errore non esplicito durante il resign dei bundle `.xctest`
  - il problema si riproduceva anche su bundle gia' validi nel `DerivedData`
- Impatto: il commit guard del repository restava rosso anche quando build, boundary guard e test mirati erano verdi, bloccando la chiusura delle tranche di cutover Rust.
- Gravita': alta
- Steps to reproduce:
  1. eseguire `xcodebuild build-for-testing` su `Solo Code-Debug`
  2. eseguire `./scripts/bootstrap_test_bundles.sh <Build/Products/Debug>`
  3. osservare il fallimento nello script durante `resolve_host_sign_identity` / `signature_is_adhoc` / `resign_path`
- Risultato attuale: il bootstrap dei bundle test poteva fallire senza errore semantico reale del bundle.
- Risultato atteso: il bootstrap deve completare con successo quando il resign/codesign dei bundle e' valido.
- Causa probabile:
  - pipeline `codesign ... | awk` e `codesign ... | grep -q` sotto `set -o pipefail`
  - `return` nudo in `resign_path()` che propagava lo status `1` di `signature_is_adhoc`
- Scope consentito:
  - [bootstrap_test_bundles.sh](/Users/benjaminstoica/SoloCode/scripts/bootstrap_test_bundles.sh)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - build/test logic dei target Swift/Rust
  - changes ai bundle test o ai target XCTest
- Moduli confinanti da verificare:
  - `solocode-validate`
  - `xcodebuild build-for-testing`
  - `test-without-building`
- Test da aggiungere o aggiornare:
  - scenario manuale verificabile: `build-for-testing` + `bootstrap_test_bundles.sh` + `solocode-validate`
- Strategia di fix minimo:
  - evitare `SIGPIPE` nelle pipeline `codesign` usando output cached in variabile
  - rendere esplicito `return 0` nel branch “firma valida, non adhoc”
- Verifica post-fix:
  - `./scripts/bootstrap_test_bundles.sh /tmp/solocode-mainchat-dd/Build/Products/Debug`
  - `./scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "...scripts/bootstrap_test_bundles.sh..." --format text`
- Commit previsto: `fix(validation): make test bundle bootstrap resilient`

## Effetto osservato
- il bootstrap dei bundle test non fallisce piu' su `pipefail`/`return` implicito
- `solocode-validate` puo' arrivare davvero allo stage test invece di fermarsi artificialmente su `testBootstrap`
