import CoderEngine
import Foundation

struct CodeReviewCommandLoopDriver: Sendable {
    typealias ClaimPendingCommands = @Sendable () -> [MCPSharedCodeReviewCommand]
    typealias ProcessClaimedCommands = @MainActor @Sendable ([MCPSharedCodeReviewCommand]) async -> Void

    private let pollIntervalNanoseconds: UInt64
    private let claimPendingCommands: ClaimPendingCommands
    private let processClaimedCommands: ProcessClaimedCommands

    init(
        pollIntervalNanoseconds: UInt64 = 350_000_000,
        claimPendingCommands: @escaping ClaimPendingCommands,
        processClaimedCommands: @escaping ProcessClaimedCommands
    ) {
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.claimPendingCommands = claimPendingCommands
        self.processClaimedCommands = processClaimedCommands
    }

    func run() async {
        while !Task.isCancelled {
            let commands = claimPendingCommands()
            if commands.isEmpty {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                continue
            }
            await processClaimedCommands(commands)
        }
    }
}
