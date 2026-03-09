# P2 — 2026-03-09 — Lo scheme `CoderEngine` non espone l'azione test

## Sintomo
L'esecuzione di:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngine'
```

fallisce subito con:

```text
Scheme CoderEngine is not currently configured for the test action.
```

## Impatto
- rallenta la validazione isolata del target engine
- spinge a testare tramite lo scheme applicativo completo, con tempi più alti
- aumenta il rischio di falsi positivi operativi quando si pensa di aver lanciato test mirati sull'engine

## Gravità
P2

## Area coinvolta
- `Solo Code.xcodeproj`
- configurazione scheme Xcode

## Riproduzione minima
1. Aprire il workspace root del progetto.
2. Eseguire `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngine'`.
3. Osservare il fallimento immediato dello scheme.

## Risultato attuale
Lo scheme `CoderEngine` può essere listato ma non usato per il test.

## Risultato atteso
Lo scheme `CoderEngine` deve consentire l'azione `test` per il target `CoderEngineTests`.

## Causa probabile
Configurazione incompleta dello scheme o mancata associazione del target test allo scheme framework.

## Mitigazione corrente
Usare lo scheme `Solo Code-Debug` con filtri `-only-testing:CoderEngineTests/...` finché lo scheme dedicato non viene corretto.
