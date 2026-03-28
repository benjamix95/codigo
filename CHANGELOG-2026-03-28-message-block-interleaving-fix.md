# Changelog — 2026-03-28

## Fix: preservare l'interleaving dei blocchi nella timeline sintetica

### Bug trovato
Quando la pipeline non forniva `toolMarker`, il fallback sintetico costruiva prima tutti i blocchi di testo e solo dopo tutti i tool event. Questo faceva apparire i blocchi “attaccati” e non più intervallati correttamente tra risposte e utilizzi tool.

### Correzione
- La timeline sintetica ora ordina i segmenti combinati per `sequence` con priorità stabile tra reasoning, testo e tool.
- I blocchi di testo visibili vengono preservati come segmenti distinti.
- I reasoning block vengono mantenuti nella timeline sintetica invece di essere sempre spostati in coda.

### Regressione aggiunta
- Copertura per il caso in cui un tool event con sequence intermedia venga renderizzato tra due blocchi primaryText.

### Verifica prevista
- Test Swift mirati su `ChatTimelineInterleavingTests`.
- Verifica del percorso sintetico e del rendering timeline interleaved.
