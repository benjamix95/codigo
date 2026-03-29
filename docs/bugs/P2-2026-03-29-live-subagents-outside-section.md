# P2 — Live sub-agents fuori sezione timeline

**Data:** 2026-03-29  
**Categoria:** B — Importante  
**Stato:** Corretto

## Problema

Le live card dei sub-agent non erano sempre incapsulate subito nella loro sezione timeline. La UX risultava incoerente rispetto ai tool group.

## Correzione

- il gruppo sub-agent ora supporta entry live e terminali
- la sezione `sub-agents` nasce subito al primo lancio
- il gruppo resta espanso finché contiene elementi `running`
- quando il gruppo chiude, la sezione si auto-collassa
