# Changelog - 2026-03-29 - Terminal task running state

## Cosa cambia
- Introdotta una normalizzazione condivisa dello stato running delle sessioni terminale.
- Gli status terminali finali (`completed`, `failed`, `success`, `done`, `cancelled`, ecc.) spengono sempre la sessione anche se `TaskActivity.isRunning` arriva sporco.
- La UI del pannello terminale ora considera live una sessione solo tramite `session.isRunning`, senza ricontrolli ridondanti su stringhe di status.

## Bug risolto
- Alcuni task terminale completati restavano mostrati come attivi con spinner o card live.

## Test
- Aggiunti test su normalizzazione running/completed e sul caso `completed` con `isRunning = true`.
