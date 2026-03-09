# 2026-03-09 — Workspace review scope for generic chat reviews

## Cosa cambia
- aggiunto lo scope review `workspace` nel motore `CodeReviewMultiSwarm`
- la main chat usa `workspace` per review generiche/architetturali senza target diff/patch/commit esplicito
- le review su diff/modifiche/staged restano su `uncommitted` o `staged` come prima
- i messaggi terminali no-files e invalid-ref del coordinator review ora usano `textReplace` invece di `textDelta`, evitando concatenazioni duplicate nel contenuto finale

## File principali
- `Engine/CoderEngine/Sources/CodeReview/Core/CodeReviewMultiSwarmProvider+Types.swift`
- `Engine/CoderEngine/Sources/CodeReview/Core/Scope/CodeReviewMultiSwarmProvider+Scope.swift`
- `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator.swift`
- `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/ReviewPipelineCoordinator+FixStage.swift`
- `Engine/CoderEngine/Sources/CodeReview/Session/ReviewSessionTypes.swift`
- `Engine/CoderEngine/Sources/Pipeline/Contracts/PipelineEnums.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Extensions/ComposerUI/ChatPanelView+PartH_CodeReviewModes.swift`

## Test
- `CoderEngineTests/CodeReviewMultiSwarmProviderTests`
- `CoderEngineTests/ReviewPipelineCoordinatorTests`
- `SoloCodeAppTests/AutoCodeReviewRoutingTests`

## Note
- fix confinato al routing scope review e al coordinator review
- nessuna modifica ai workflow patch/apply/revalidate
