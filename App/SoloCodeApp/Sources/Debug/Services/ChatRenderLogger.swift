import Foundation
import os.log

// MARK: - ChatRenderLogger

/// Lightweight render-cycle logger for diagnosing unnecessary SwiftUI redraws
/// in the main chat pipeline. Uses `os_log` (visible in Console.app / Xcode
/// console) with subsystem "com.solocode.render" and category "chat".
///
/// Enable / disable at runtime via `ChatRenderLogger.isEnabled`.
/// All calls are no-ops when disabled — zero overhead in production.
///
/// Thread-safe: uses `os_unfair_lock` for the throttle map so it can be
/// called from both the main thread (SwiftUI body) and background threads
/// (interleaver, parsers).
enum ChatRenderLogger {

    /// Master switch — set to `false` to silence all render logs.
    nonisolated(unsafe) static var isEnabled = true

    // MARK: - Private

    private static let subsystem = "com.solocode.render"
    private static let log = OSLog(subsystem: subsystem, category: "chat")

    /// Throttle map protected by an unfair lock for thread safety.
    nonisolated(unsafe) private static var lastLogTime: [String: CFAbsoluteTime] = [:]
    nonisolated(unsafe) private static var lock = os_unfair_lock()

    /// Minimum interval (seconds) between two consecutive logs for the
    /// *same* caller label. 0.25 s ≈ max 4 logs/sec per label.
    private static let throttleInterval: CFAbsoluteTime = 0.25

    // MARK: - Public API

    /// Log a render event. Automatically throttled per `label`.
    static func logRender(_ label: String, detail: String? = nil) {
        guard isEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()

        var shouldLog = false
        os_unfair_lock_lock(&lock)
        if let last = lastLogTime[label], (now - last) < throttleInterval {
            // Throttled — skip.
        } else {
            lastLogTime[label] = now
            shouldLog = true
        }
        os_unfair_lock_unlock(&lock)

        guard shouldLog else { return }
        if let detail {
            os_log(.debug, log: log, "[RENDER] %{public}@ — %{public}@", label, detail)
        } else {
            os_log(.debug, log: log, "[RENDER] %{public}@", label)
        }
    }

    /// Log an onChange trigger. NOT throttled.
    static func logOnChange(_ label: String, detail: String? = nil) {
        guard isEnabled else { return }
        if let detail {
            os_log(.debug, log: log, "[ONCHANGE] %{public}@ — %{public}@", label, detail)
        } else {
            os_log(.debug, log: log, "[ONCHANGE] %{public}@", label)
        }
    }

    /// Log a reason why a view's Equatable check returned `false`.
    static func logEquatableMiss(_ label: String, reason: String) {
        guard isEnabled else { return }
        os_log(.debug, log: log, "[EQ-MISS] %{public}@ — %{public}@", label, reason)
    }

    /// Log a timed operation (body evaluation, layout pass, etc.).
    /// Call `startTiming()`, do work, then call `endTiming()`.
    static func startTiming(_ label: String) -> CFAbsoluteTime {
        CFAbsoluteTimeGetCurrent()
    }

    /// End a timed operation and log if it exceeded the threshold.
    /// - Parameters:
    ///   - label: The operation name.
    ///   - start: Value returned by `startTiming`.
    ///   - thresholdMs: Only log if elapsed time exceeds this (default 2ms).
    static func endTiming(_ label: String, start: CFAbsoluteTime, thresholdMs: Double = 2.0) {
        guard isEnabled else { return }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        if elapsed >= thresholdMs {
            os_log(.debug, log: log, "[SLOW] %{public}@ — %.1fms", label, elapsed)
        }
    }

    /// Log a main thread stall (e.g., file lock, sync I/O).
    static func logMainThreadStall(_ label: String, durationMs: Double) {
        guard isEnabled else { return }
        os_log(.error, log: log, "[MAIN-STALL] %{public}@ — %.0fms blocked", label, durationMs)
    }

    /// Reset the throttle map.
    static func resetThrottles() {
        os_unfair_lock_lock(&lock)
        lastLogTime.removeAll()
        os_unfair_lock_unlock(&lock)
    }
}
