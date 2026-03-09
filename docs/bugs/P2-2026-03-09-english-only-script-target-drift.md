# P2 - english-only check punta a directory legacy inesistenti

## Categoria
- B

## Bug
- Lo script `scripts/check_english_only.sh` cercava stringhe in `CoderEngine/Sources`, `Sources/CoderIDE` e `CoderEngine/Tests`, ma questi path non corrispondono più alla struttura reale del repository.

## Sintomo
- Lo script non copre i sorgenti canonici attuali e può restituire risultati incompleti o fuorvianti.

## Impatto
- Verifica di qualità meno affidabile.
- Falso senso di copertura sui testi non-English.

## Gravità
- P2

## Steps to reproduce
1. Aprire `scripts/check_english_only.sh`.
2. Controllare il blocco `TARGETS`.
3. Verificare che i path legacy non esistano più nel repository corrente.

## Risultato attuale
- Parte del codice reale non viene analizzata.

## Risultato atteso
- Lo script deve puntare ai path canonici attuali di app, engine e test.

## Causa probabile
- Drift residuo da layout precedente del progetto.

## Scope consentito
- `scripts/check_english_only.sh`
- documentazione `docs/bugs` e `docs/changelog`

## Non-scope
- Cambiare la policy dei pattern ricercati
- Espandere la copertura ad altri linguaggi o cartelle non già previste

## Moduli confinanti da verificare
- `App/SoloCodeApp/Sources`
- `Engine/CoderEngine/Sources`
- `Tests/CoderEngineTests`
- `Tests/SoloCodeAppTests`

## Test da aggiungere o aggiornare
- Verifica manuale tramite esecuzione dello script.

## Strategia di fix minimo
- Aggiornare esclusivamente i target filesystem dello script.

## Verifica post-fix
- `./scripts/check_english_only.sh`

## Commit previsto
- `fix(scripts): align english-only check with current source tree`
