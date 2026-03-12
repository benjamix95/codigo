# [P1] Il copy post-build del binario MCP Rust invalidava la firma del bundle app

## Contesto
- durante l’integrazione del binario `coderide-mcp-server-rust` nel bundle macOS
- il file veniva copiato dopo `xcodebuild build`

## Sintomo
- `scripts/validate_app_bundle.sh` falliva con:
  - `a sealed resource is missing or invalid`

## Impatto
- il bundle risultava non verificabile
- build script e packaging locale diventavano inaffidabili
- rischio diretto di distribuire un bundle apparentemente corretto ma con firma invalida

## Causa probabile
- il copy del nuovo eseguibile MCP Rust avveniva dopo la firma effettuata da Xcode
- il bundle non veniva rifirmato dopo la mutazione del contenuto

## Fix applicato
- aggiunta build script dedicata per il server Rust MCP
- copia del binario Rust nel bundle
- rifirma esplicita del bundle dopo la copia in:
  - `scripts/build-app.sh`
  - `scripts/run-app.sh`

## Verifica
- smoke test bundle:
  - build binario Rust
  - copy in `Solo Code.app/Contents/MacOS`
  - `codesign --force --deep`
  - `scripts/validate_app_bundle.sh`

## Stato
- risolto in questa tranche
