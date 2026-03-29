# P1 — Timeline sub-agent completati rumorosa e deduplica stale

**Data:** 2026-03-29  
**Categoria:** B — Importante  
**Stato:** Corretto nel fix della sezione collassabile sub-agent

## Problema

La timeline chat mostrava i sub-agent terminali come card autonome sparse nel turno. Inoltre, in presenza di snapshot persistiti e stato live dello stesso swarm, la deduplica non esplicitava una fonte preferita e poteva lasciare visibile uno stato stale.

## Bug trovati

### 1. Sub-agent terminali non raccolti in una sezione collassabile
- **Impatto:** la chat perde pulizia e la lettura del turno diventa più rumorosa, soprattutto con 2+ sub-agent completati.
- **Comportamento corretto:** i `running` restano inline; i `completed` e `failed` finiscono in una sola sezione collassabile.

### 2. Snapshot persistito dello stesso swarm può restare visibile mentre il live card è ancora attivo
- **Impatto:** si può esporre uno stato terminale vecchio accanto a uno swarm che in realtà è ancora `running`.
- **Comportamento corretto:** lo snapshot viene escluso se esiste un live card `running` dello stesso `swarmId`; se il live è terminale, il live terminale vince sul persistito.

## Correzione applicata

- nuovo segmento timeline aggregato per i sub-agent terminali
- sezione UI collassabile dedicata ai sub-agent completati/falliti
- deduplica per `swarmId` con precedenza allo stato live
- fallback legacy riallineato alla stessa regola
