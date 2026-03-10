# 2026-03-10 — Finalizzazione coerente dei raw update nel review panel

## Modifiche
- introdotta una coda di `ReviewRunDeferredMutation` per i raw update differiti del panel
- `finishPanelActionOutput(...)` e `failPanelActionOutput(...)` flushano le mutazioni pendenti prima della finalize
- i late update su run già chiusi non ricreano più una response bubble in streaming

## Test
- aggiunti:
  - `testFinishPanelActionFlushesDeferredReviewRunSections`
  - `testFinishPanelActionDoesNotRecreateDeferredResponseBubble`

## Rischio controllato
- mantenuto il deferral dei publish fuori dal render pass
- evitata la race tra finalize e raw event in coda
