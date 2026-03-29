import XCTest
@testable import CoderIDE

final class SwarmCardPresentationPartitionTests: XCTestCase {
    func testPartitionKeepsOnlyRunningCardsInActiveBucket() {
        let cards = [
            SwarmLiveCardState(swarmId: "sa-a", status: .running),
            SwarmLiveCardState(swarmId: "sa-b", status: .completed),
            SwarmLiveCardState(swarmId: "sa-c", status: .failed),
        ]

        let partition = partitionSubagentCardsForPresentation(cards)

        XCTAssertEqual(partition.active.map(\.swarmId), ["sa-a"])
        XCTAssertEqual(partition.finished.map(\.swarmId), ["sa-b", "sa-c"])
    }
}
