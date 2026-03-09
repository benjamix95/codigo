# 2026-03-09 — Cross-process lock fail-safe fallback

## Modifiche
- sostituito il comportamento `fatalError` dei lock cross-process review e bughunter con un helper condiviso che tenta il file lock e degrada in fallback locale solo se il lock advisory non è ottenibile
- aggiunto retry mirato su `ENOENT` per ricreare la directory del lock ed evitare crash quando il path viene ricostruito fuori fase
- mantenuto invariato il path principale quando `open()` e `flock()` riescono, con rilascio ordinato di `LOCK_UN` e `close()`
- delegato `withBugHunterFileLock` al nuovo helper condiviso per evitare duplicazione della logica di lock

## Test
- aggiunta regressione review per fallback locale su `ENOENT`
- aggiunta regressione review per serializzazione concorrente del fallback su `EMFILE`
- aggiunta suite dedicata bughunter per fallback locale e serializzazione concorrente

## Rischio controllato
- il fallback usa `NSRecursiveLock` e quindi garantisce serializzazione solo intra-processo quando il file lock OS non è disponibile
- il tradeoff è intenzionale: evitare corruzione locale e crash del processo, lasciando invariato il comportamento cross-process nei casi normali
