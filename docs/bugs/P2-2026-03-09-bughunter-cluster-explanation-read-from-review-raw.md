# P2 — BugHunter cluster explanation leggeva ancora i finding review raw

## Categoria
Categoria B

## Bug
Il comando `bughunter_explain_cluster` costruiva il cluster principale usando `reviewSnapshot.findings`, quindi non passava dal canonical snapshot `VerifiedFindings`.

## Sintomo
L’explain cluster poteva includere o escludere finding sulla base del vecchio layer review, invece delle entity condivise di dominio.

## Impatto
La UX `BugHunter` restava incoerente: status/autofix già leggevano dal shared state, mentre la cluster explanation no.

## Gravità
Media

## Riproduzione
1. Creare una review session collegata a `BugHunter`.
2. Popolare `verifiedFindings` con finding `bug` e `security`.
3. Invocare `bughunter_explain_cluster`.
4. Prima del fix, la spiegazione dipende dal modello review raw e non dal canonical snapshot.

## Causa probabile
Il comando è rimasto ancorato al vecchio modello review, mentre il rollout shared è arrivato in tranche successive.

## Fix applicato
- `bughunter_explain_cluster` ora usa `VerifiedFindingsService`
- il clustering considera solo `domain == bug`
- aggiunto test di regressione che esclude finding security dal cluster bug
