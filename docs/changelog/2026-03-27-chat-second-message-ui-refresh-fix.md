# 2026-03-27 — Fix refresh chat dopo secondo messaggio

## Modifiche

- aggiunto un hook `onReceive(chatStore.objectWillChange)` nell’area messaggi per riallineare sempre `messagesConversationSnapshot` quando il `ChatStore` pubblica cambiamenti tardivi/non coperti dai trigger esistenti;
- introdotta la policy `shouldPreserveSnapshotAgainstTransientEmptyStore(...)` per evitare che uno store vuoto transiente dello stesso thread rimpiazzi uno snapshot non vuoto durante o subito dopo la fine del task;
- tracciato `snapshotLastBusyAt` in `ChatPanelView` per estendere la protezione anche nella breve finestra post-stream;
- aggiunto `flushConversationChangeNotification()` in `ChatStore.endTask(...)` per svuotare subito eventuali notifiche conversazione coalesciate;
- aggiunti test di regressione:
  - `ChatPanelMessageSnapshotPolicyTests`
  - `ChatStoreTaskOwnershipTests.testFlushConversationChangeNotificationPublishesPendingStreamingMutationImmediately`

## Fix iterativo (seconda passata)

- aggiunto hook `onReceive(pipelineIntegrationService.objectWillChange)` per riallineare lo snapshot durante il pipeline streaming — `chatStore.objectWillChange` è throttlato a 150ms, ma il pipeline service pubblica ogni ~32ms;
- estesa la policy `shouldPreserveSnapshotAgainstTransientEmptyStore` per proteggere anche contro riduzione parziale dei messaggi (`freshMessageCount < previousSnapshotMessageCount`), non solo store completamente vuoto;
- aggiunti 5 test di regressione per il caso di message count reduction parziale in `ChatPanelMessageSnapshotPolicyTests`.

## Obiettivo del fix

Evitare che la timeline della chat sparisca o resti visivamente ferma dopo il secondo messaggio, specialmente quando gli aggiornamenti dello store arrivano in ritardo rispetto al cambio di stato busy/idle o il Rust bridge ritorna transientemente un numero ridotto di messaggi.
