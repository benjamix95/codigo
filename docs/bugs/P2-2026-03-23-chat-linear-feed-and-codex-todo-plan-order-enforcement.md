# P2 - 2026-03-23 - Chat main thread still exposed trace-style tool surfaces and Codex could start operational work before todo/plan

## Sintomi

- la chat mostrava una vista separata di tool trace invece di una timeline unica
- la UI esponeva riferimenti espliciti a `MCP call`, `coderide_*` e nomi tool tecnici
- Codex in chat `Agent` poteva partire con read/command/subagent prima di `todo_write`
- anche dopo il todo, poteva proseguire senza un vero `plan_create`

## Impatto

L'esperienza non risultava lineare e sembrava una console di orchestrazione interna:

- ordine cronologico percepito debole
- strumenti esposti come superficie tecnica invece che come comportamento nativo
- task multi-step non abbastanza vincolati a `todo -> plan -> execution`

## Causa probabile

Due problemi distinti:

1. la bubble assistant separava `primaryText`, todo card e `MessageToolTraceView`
2. il runtime live bloccava solo `policy_ack`, ma non l'ordine operativo richiesto per Codex

## Fix applicato

- la bubble assistant usa un feed operativo lineare interno invece del trace widget separato
- le etichette UI ripuliscono i riferimenti MCP/coderide
- per `codex-cli` in `Agent` mode il runtime ora blocca:
  - qualunque evento operativo prima di `todo_write`
  - qualunque evento operativo non-plan dopo il todo ma prima di `plan_create`

## Regressioni da coprire

- feed chat senza `MessageToolTraceView`
- assenza di etichette `MCP call` / `coderide_*` nella bubble assistant
- blocco `todo_first_required`
- blocco `plan_after_todo_required`
