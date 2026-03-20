# 2026-03-20 — Fix bootstrap test bundles per validation

## Modifiche
- aggiornato [bootstrap_test_bundles.sh](/Users/benjaminstoica/SoloCode/scripts/bootstrap_test_bundles.sh):
  - `resolve_host_sign_identity()` non usa piu' una pipeline `codesign | awk` fragile sotto `pipefail`
  - `signature_is_adhoc()` non usa piu' una pipeline `codesign | grep -q` che poteva chiudersi con `SIGPIPE`
  - `resign_path()` usa `return 0` esplicito quando la firma e' gia' valida e non adhoc
- aggiunto il bug record [P1-2026-03-20-test-bundle-bootstrap-failed-on-pipefail-and-bare-return.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-20-test-bundle-bootstrap-failed-on-pipefail-and-bare-return.md)

## Risultato
- `bootstrap_test_bundles.sh` completa il resign dei bundle test senza uscire artificialmente con `141` o `1`
- il commit guard `solocode-validate` puo' attraversare lo stage `testBootstrap` e arrivare ai test veri

## Verifica
- `./scripts/bootstrap_test_bundles.sh /tmp/solocode-mainchat-dd/Build/Products/Debug`
- `./scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "scripts/bootstrap_test_bundles.sh" --format text`
