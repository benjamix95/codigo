import CoderEngine
import Foundation

struct BugHunterCommandLoopDriver: Sendable {
    typealias ClaimPendingCommands = @Sendable () -> [MCPSharedBugHunterCommand]
    typealias ClaimHookEvents = @Sendable () -> [MCPSharedBugHunterHookEvent]
    typealias ProcessInputs = @MainActor @Sendable ([MCPSharedBugHunterCommand], [MCPSharedBugHunterHookEvent]) async -> Void

    private let pollIntervalNanoseconds: UInt64
    private let claimPendingCommands: ClaimPendingCommands
    private let claimHookEvents: ClaimHookEvents
    private let processInputs: ProcessInputs

    init(
        pollIntervalNanoseconds: UInt64 = 450_000_000,
        claimPendingCommands: @escaping ClaimPendingCommands,
        claimHookEvents: @escaping ClaimHookEvents,
        processInputs: @escaping ProcessInputs
    ) {
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.claimPendingCommands = claimPendingCommands
        self.claimHookEvents = claimHookEvents
        self.processInputs = processInputs
    }

    func run() async {
        while !Task.isCancelled {
            let commands = claimPendingCommands()
            let hookEvents = claimHookEvents()
            if commands.isEmpty && hookEvents.isEmpty {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                continue
            }
            await processInputs(commands, hookEvents)
        }
    }
}
