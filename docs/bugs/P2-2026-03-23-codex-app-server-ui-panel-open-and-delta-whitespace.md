# P2 - 2026-03-23 - Codex app-server completes MCP todo/plan calls but main chat UI does not open panels and trims streamed spacing

## Sintomo

Con `codex app-server`, il trace mostra `coderide_todo_write` e `coderide_plan_create`, ma:

- il task panel non si apre automaticamente
- il plan panel puo' restare chiuso anche dopo `plan_create`
- la risposta finale puo' arrivare con parole attaccate o newline persi

## Impatto

Il backend usa i tool MCP corretti, ma l'utente percepisce che Codex non abbia eseguito `todo` e `plan`. In piu', il rendering del testo finale peggiora la leggibilita' e rende la sessione apparentemente corrotta.

## Causa probabile

Due cause separate:

1. il bridge UI aggiornava solo parzialmente lo stato di apertura pannelli
2. il transport Rust `codex_app_server` leggeva i delta testuali tramite helper che fa `trim`, perdendo spazi e newline significativi

## Fix

- introdotta una policy testabile per l'apertura del plan panel
- introdotta una policy testabile per abilitare il task panel nei mode operativi
- `codex_app_server` ora legge i delta con accesso raw, senza trimming

## Regressioni da coprire

- apertura automatica del plan panel dopo `automaticFlow`
- apertura del task panel nei mode operativi
- preservazione di whitespace/newline nei delta `item/agentMessage/delta`
