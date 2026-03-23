# 2026-03-23 - Codex tool-first streaming and plan build fallback

## Modifiche

- il transport Codex `app-server` non mostra piu' il testo iniziale prima del primo tool operativo
- la chat torna a mostrare i todo legacy/unscoped quando mancano todo scope-ati
- il plan panel puo' lanciare `Build` anche per board creati via `plan_create` con goal+steps ma senza `chosen_path`

## Verifica

- test Rust per il gate dei delta prima del primo tool operativo
- test Swift per il fallback build content
- test Swift per la visibilita' dei todo con fallback legacy
