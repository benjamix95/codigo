# Changelog — 2026-03-28 — Sidebar thread activity gate

## Fix
- Reso più stretto il gate della sidebar: la card mostra spinner/stato di risposta solo quando nel thread esiste attività visibile concreta.
- Evitato che un runtime task orfano, senza activity reale nel `TaskActivityStore`, tenga accesa la card come se fosse “in risposta”.
- Allineato `statusText` allo stesso gate: nessun testo di attività viene mostrato quando non ci sono activity concrete.

## Test
- Aggiunta regressione per il caso in cui il task runtime è presente ma non esistono attività visibili.
- Aggiornati i test di fingerprint/render state per usare activity concrete, così il contratto della sidebar resta coerente.

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SidebarThreadSnapshotTests`
- Esito: success
