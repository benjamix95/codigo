# SwiftUI: “Modifying state during view update” in streaming timeline merge

**Data:** 2026-03-29  
**Radar/issue:** Solo Code – 10549  
**File:** `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartD_StreamingTimelineMerge.swift`

## Sintomo

Runtime warning SwiftUI sulla riga che chiamava `conversationRuntime.cachePipelineTurnStateForAssistantMessage(turn)` dentro `messageForStreamingTimelineDisplay`.

## Causa

`messageForStreamingTimelineDisplay` è usato nel percorso di costruzione/rendering della lista messaggi. `conversationRuntime` è `@State` su `ChatPanelView`; mutarlo durante quel percorso viola il ciclo di aggiornamento di SwiftUI.

## Fix

Spostare la cache su `Task { @MainActor in … }` così la scrittura avviene dopo il frame corrente. Il merge della stessa invocazione continua a usare `turn` già risolto dalla `resolution`; la cache serve ai frame successivi.

## Verifica

- `xcodebuild -project "Solo Code.xcodeproj" -scheme "Solo Code-Debug" -destination 'platform=macOS' build`
