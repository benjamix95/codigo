# P2 - 2026-03-23 - Codex main chat streams prose before tools, hides unscoped todos in chat, and cannot build from MCP-created plans without chosen_path

## Sintomi

- Codex puo' emettere testo visibile prima del primo tool operativo
- i `todo_write` arrivano nel runtime ma non compaiono nella card todo in chat quando i todo sono senza scope conversazione
- il pulsante `Build` del plan non parte per board creati via `plan_create` con goal+steps ma senza `chosen_path`

## Impatto

L'integrazione sembra ancora parzialmente non conforme anche quando i tool MCP vengono usati davvero:

- l'utente vede preamboli LLM prima dei tool
- i todo sembrano mancanti nella chat
- il plan panel mostra un piano ma il build non ha un payload eseguibile

## Causa probabile

Tre cause distinte:

1. il transport `codex app-server` inoltra subito i `textDelta`
2. `displayTodosForChat` richiede scope stretto e non recupera i todo legacy/unscoped
3. il plan panel considera eseguibile solo `chosen_path`, ma `plan_create` MCP puo' produrre solo goal+steps

## Fix

- buffer dei `textDelta` Codex fino al primo evento operativo non-`policy_ack`
- fallback legacy per i todo unscoped quando non esistono todo scope-ati per la conversazione
- generazione di un contenuto build fallback da `goal + steps` con sezione `## Todo`
