import Foundation

// MARK: - Memory Leak Detector

/// Detector di memory leak basato su monitoraggio allocazioni e reference counting.
actor MemoryLeakDetector {
    /// Informazione su un potenziale leak rilevato.
    struct LeakInfo: Identifiable, Sendable {
        let id: String
        let className: String
        let address: String
        let size: Int
        let retainCount: Int
        let detectedAt: Date
        let backtrace: String?
    }

    /// Snapshot della memoria in un dato istante.
    struct MemorySnapshot: Sendable {
        let timestamp: Date
        let residentMemoryMB: Double
        let virtualMemoryMB: Double
        let leaks: [LeakInfo]
    }

    private var detectedLeaks: [LeakInfo] = []
    private var snapshots: [MemorySnapshot] = []
    private let maxSnapshots = 100

    // MARK: - Rilevamento

    /// Esegue un'analisi dei leak sul processo corrente.
    func detectLeaks() async -> [LeakInfo] {
        let pid = ProcessInfo.processInfo.processIdentifier
        let result = await runLeaksCommand(pid: pid)

        guard let output = result else {
            return detectedLeaks
        }

        let newLeaks = parseLeaksOutput(output)
        detectedLeaks = newLeaks
        return newLeaks
    }

    /// Cattura uno snapshot della memoria corrente.
    func captureSnapshot() async -> MemorySnapshot {
        let memory = currentMemoryUsage()
        let leaks = detectedLeaks

        let snapshot = MemorySnapshot(
            timestamp: Date(),
            residentMemoryMB: memory.resident,
            virtualMemoryMB: memory.virtual,
            leaks: leaks
        )

        snapshots.append(snapshot)
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst(snapshots.count - maxSnapshots)
        }

        return snapshot
    }

    /// Restituisce il numero di leak attualmente rilevati.
    func currentLeakCount() -> Int {
        detectedLeaks.count
    }

    /// Restituisce gli snapshot recenti.
    func recentSnapshots(limit: Int = 20) -> [MemorySnapshot] {
        Array(snapshots.suffix(limit))
    }

    /// Resetta lo stato del detector.
    func reset() {
        detectedLeaks = []
        snapshots = []
    }

    // MARK: - Privato

    private func runLeaksCommand(pid: Int32) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/leaks")
            process.arguments = [String(pid), "--noContent"]

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            process.terminationHandler = { _ in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)
                continuation.resume(returning: output)
            }
        }
    }

    private func parseLeaksOutput(_ output: String) -> [LeakInfo] {
        let lines = output.components(separatedBy: .newlines)
        var leaks: [LeakInfo] = []

        // Formato tipico di leaks:
        // Leak: 0x... size=N <ClassName>
        let leakPattern = try? NSRegularExpression(
            pattern: #"Leak:\s+(0x[0-9a-f]+)\s+size=(\d+)\s+(.+)"#,
            options: .caseInsensitive
        )

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let regex = leakPattern,
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
                let address = extractGroup(from: trimmed, match: match, group: 1)
                let sizeStr = extractGroup(from: trimmed, match: match, group: 2)
                let className = extractGroup(from: trimmed, match: match, group: 3)

                leaks.append(LeakInfo(
                    id: address,
                    className: className,
                    address: address,
                    size: Int(sizeStr) ?? 0,
                    retainCount: 0,
                    detectedAt: Date(),
                    backtrace: nil
                ))
            }
        }

        return leaks
    }

    private func extractGroup(from string: String, match: NSTextCheckingResult, group: Int) -> String {
        guard let range = Range(match.range(at: group), in: string) else { return "" }
        return String(string[range])
    }

    private func currentMemoryUsage() -> (resident: Double, virtual: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rawPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, 0)
        }

        let residentMB = Double(info.resident_size) / (1024 * 1024)
        let virtualMB = Double(info.virtual_size) / (1024 * 1024)
        return (residentMB, virtualMB)
    }
}
