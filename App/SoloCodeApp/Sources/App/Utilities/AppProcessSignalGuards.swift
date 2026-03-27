import Darwin
import Foundation

struct AppIgnoredSignalSpec: Equatable {
    let number: Int32
    let name: String
}

func appIgnoredSignalSpecs() -> [AppIgnoredSignalSpec] {
    [
        AppIgnoredSignalSpec(number: SIGHUP, name: "SIGHUP"),
        AppIgnoredSignalSpec(number: SIGPIPE, name: "SIGPIPE"),
    ]
}

private enum AppProcessSignalGuards {
    private static let lock = NSLock()
    private static var installed = false

    static func installIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        for spec in appIgnoredSignalSpecs() {
            signal(spec.number, SIG_IGN)
        }
        installed = true
    }
}

func installAppProcessSignalGuardsIfNeeded() {
    AppProcessSignalGuards.installIfNeeded()
}
