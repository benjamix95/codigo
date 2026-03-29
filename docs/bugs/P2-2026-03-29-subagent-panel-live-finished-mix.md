# P2 — Panel e strip sub-agents mescolano live e finiti

**Data:** 2026-03-29  
**Categoria:** B — Importante  
**Stato:** Corretto

## Problema

Le superfici secondarie dei sub-agent non separavano chiaramente gli attivi dai completati/falliti e quindi continuavano a sembrare “live” anche quando non lo erano più.

## Fix

- introdotta una partizione condivisa `active` / `finished`
- strip inline aggiornata per mostrare solo gli attivi nella sezione live e i finiti in una sezione separata
- panel overview aggiornato con sezioni distinte e stato visivo più chiaro
- spinner sub-agent reso più rapido e con meno tacche
