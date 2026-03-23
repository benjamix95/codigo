# P1 - Release script usa path legacy e bundle errato

## Categoria
- B

## Bug
- Lo script di release invocava `./Scripts/build-app.sh` invece di `./scripts/build-app.sh` e provava a zippare `Solo Code.app` dal root, non il bundle prodotto in `dist/`.

## Sintomo
- Il comando di release non è coerente con il layout reale del repository.

## Impatto
- Packaging di release fragile o fallibile.
- Documentazione e script divergenti.

## Gravità
- P1

## Steps to reproduce
1. Aprire `scripts/release.sh`.
2. Verificare il path `./Scripts/build-app.sh`.
3. Verificare il comando zip che usa `Solo Code.app` dal root.

## Risultato attuale
- Lo script non punta allo script reale e non zippa il bundle generato dal flusso corrente.

## Risultato atteso
- Lo script deve usare `scripts/build-app.sh` e creare lo zip dal bundle presente in `dist/`.

## Causa probabile
- Drift residuo da naming/struttura precedente del progetto.

## Scope consentito
- `scripts/release.sh`
- `README.md`
- documentazione bug/changelog

## Non-scope
- Rinomina prodotto applicativo
- Cambiamento del formato di distribuzione

## Moduli confinanti da verificare
- `scripts/build-app.sh`
- `docs/release-notes`
- `docs/update/manifest.json`

## Test da aggiungere o aggiornare
- Verifica manuale dello script con `--help`.

## Strategia di fix minimo
- Sostituire il path legacy con quello reale.
- Comprimere il bundle prodotto in `dist/` senza introdurre ulteriori cambiamenti al flusso release.

## Verifica post-fix
- `./scripts/release.sh --help`
- ispezione statica del blocco finale di packaging

## Commit previsto
- `fix(release): align build script path and release bundle packaging`
