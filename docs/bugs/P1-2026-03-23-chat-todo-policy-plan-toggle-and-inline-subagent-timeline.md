# P1 — Chat todo policy, plan toggle e timeline subagent

## Problemi trovati

### 1. Hard block troppo aggressivo su `todo -> plan -> esecuzione`
- Gravità: P1
- Sintomo: la chat emetteva `Todo required before execution` e poi `Plan required after todo` anche per discovery non mutativa o `skill`.
- Impatto: bloccava flussi normali di analisi, skill e subagent prima ancora della vera esecuzione.
- Stato: corretto il 2026-03-23.

### 2. Toggle plan apriva il panel implicitamente
- Gravità: P1
- Sintomo: attivare `planToggleEnabled` apriva il Plan panel anche senza richiesta esplicita dell’utente.
- Impatto: il panel si apriva troppo presto, prima di chiarimenti o piano pronto.
- Stato: corretto il 2026-03-23.

### 3. Timeline chat troppo aggregata per task live e subagent
- Gravità: P2
- Sintomo: il turno assistant mostrava soprattutto un blocco trace aggregato; le card subagent live non erano collegate alla timeline principale.
- Impatto: la progressione dei task risultava poco lineare e poco leggibile.
- Stato: mitigato il 2026-03-23 con feed inline live e card subagent collegate alla chat.

### 4. Snapshot subagent senza transcript persistibile
- Gravità: P2
- Sintomo: a task concluso restava solo una preview sintetica.
- Impatto: perdita del contesto live del subagent nella cronologia chat.
- Stato: corretto il 2026-03-23 con transcript persistibile opzionale e retrocompatibile.
