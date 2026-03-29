# P2 — Sezione sub-agent completati troppo aggregata

**Data:** 2026-03-29  
**Categoria:** B — Importante  
**Stato:** Corretto

## Problema

La timeline raggruppava tutti i sub-agent completati del turno in un unico blocco collassabile, anche quando erano stati lanciati in ondate diverse.

## Effetto

- si perde la distinzione tra lanci separati
- la timeline non rispecchia il comportamento “a sezioni” dei tool
- i gruppi diventano troppo grandi e poco informativi

## Fix

- supporto a più `completedSubagentsGroup` nello stesso turno
- split per coorti cronologiche di lancio
- fallback: i sub-agent con anchor molto vicine restano nello stesso gruppo
