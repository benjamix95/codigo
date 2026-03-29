import Foundation

struct SwarmCardPresentationPartition {
    let active: [SwarmLiveCardState]
    let finished: [SwarmLiveCardState]
}

func partitionSubagentCardsForPresentation(
    _ cards: [SwarmLiveCardState]
) -> SwarmCardPresentationPartition {
    SwarmCardPresentationPartition(
        active: cards.filter { $0.status == .running },
        finished: cards.filter { $0.status != .running }
    )
}
