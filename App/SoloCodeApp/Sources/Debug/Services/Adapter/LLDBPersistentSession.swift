import Foundation

protocol LLDBCommandSession: Sendable {
    func send(commands: [String]) async throws -> String
    func close() async
}

enum LLDBPersistentSessionError: Error, LocalizedError, Equatable {
    case startFailed(String)
    case terminated
    case timeout
    case noCommands

    var errorDescription: String? {
        switch self {
        case .startFailed(let reason):
            return reason
        case .terminated:
            return "Sessione LLDB terminata."
        case .timeout:
            return "Timeout durante l'esecuzione del comando LLDB."
        case .noCommands:
            return "Nessun comando LLDB da eseguire."
        }
    }
}

actor LLDBPersistentSession: LLDBCommandSession {
    private let process: Process
    private let stdinHandle: FileHandle
    private let outputBuffer = LLDBPersistentOutputBuffer()
    private let commandTimeoutNanoseconds: UInt64
    private var stdoutReader: Task<Void, Never>?
    private var stderrReader: Task<Void, Never>?
    private var isClosed = false

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
        arguments: [String] = ["lldb", "--no-lldbinit"],
        commandTimeoutNanoseconds: UInt64 = 8_000_000_000
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw LLDBPersistentSessionError.startFailed("Impossibile avviare LLDB: \(error.localizedDescription)")
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.commandTimeoutNanoseconds = commandTimeoutNanoseconds

        let outputBuffer = self.outputBuffer
        stdoutReader = Task.detached {
            while !Task.isCancelled {
                let data = stdoutPipe.fileHandleForReading.availableData
                if data.isEmpty {
                    await outputBuffer.markStreamClosed()
                    break
                }
                await outputBuffer.append(data)
            }
        }

        stderrReader = Task.detached {
            while !Task.isCancelled {
                let data = stderrPipe.fileHandleForReading.availableData
                if data.isEmpty {
                    await outputBuffer.markStreamClosed()
                    break
                }
                await outputBuffer.append(data)
            }
        }
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
    }

    func send(commands: [String]) async throws -> String {
        guard !commands.isEmpty else { throw LLDBPersistentSessionError.noCommands }
        guard !isClosed else { throw LLDBPersistentSessionError.terminated }
        guard process.isRunning else { throw LLDBPersistentSessionError.terminated }

        let markerSuffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let marker = "__CODERIDE_LLDB_EOT_\(markerSuffix)__"
        let legacyMarker = "__CODERIDE_LDBB_EOT_\(markerSuffix)__"
        let commandStartOffset = await outputBuffer.currentOffset()
        let markerCommand = "script print(\"\(marker)\")"
        let payload = (commands + [markerCommand])
            .map { "\($0)\n" }
            .joined()

        try writeToStdin(Data(payload.utf8))
        return try await outputBuffer.waitForMarker(
            marker,
            legacyMarker: legacyMarker,
            fromOffset: commandStartOffset,
            timeoutNanoseconds: commandTimeoutNanoseconds
        )
    }

    func close() async {
        guard !isClosed else { return }
        isClosed = true

        try? writeToStdin(Data("quit\n".utf8))
        stdinHandle.closeFile()

        if process.isRunning {
            process.terminate()
        }

        stdoutReader?.cancel()
        stderrReader?.cancel()
        stdoutReader = nil
        stderrReader = nil
        await outputBuffer.forceClose()
    }

    private func writeToStdin(_ data: Data) throws {
        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            throw LLDBPersistentSessionError.terminated
        }
    }
}

private actor LLDBPersistentOutputBuffer {
    private var data = Data()
    private var baseOffset = 0
    private var closedStreams = 0
    private var forciblyClosed = false
    private let pollIntervalNanoseconds: UInt64 = 20_000_000

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        data.append(chunk)
    }

    func markStreamClosed() {
        closedStreams += 1
    }

    func forceClose() {
        forciblyClosed = true
    }

    func currentOffset() -> Int {
        baseOffset + data.count
    }

    func waitForMarker(
        _ marker: String,
        legacyMarker: String?,
        fromOffset: Int,
        timeoutNanoseconds: UInt64
    ) async throws -> String {
        let markerData = Data(marker.utf8)
        let legacyMarkerData = legacyMarker.map { Data($0.utf8) }
        let deadline = DispatchTime.now().uptimeNanoseconds &+ timeoutNanoseconds

        while true {
            let localStart = max(0, fromOffset - baseOffset)
            if localStart <= data.count {
                if let markerRange = data.range(
                    of: markerData,
                    options: [],
                    in: localStart ..< data.count
                ) {
                    let segment = data[localStart ..< markerRange.lowerBound]
                    let output = String(decoding: segment, as: UTF8.self)
                    trimBuffer(consumedLocalOffset: markerRange.upperBound)
                    return output
                }

                if let legacyMarkerData,
                   let legacyMarkerRange = data.range(
                    of: legacyMarkerData,
                    options: [],
                    in: localStart ..< data.count
                   )
                {
                    let segment = data[localStart ..< legacyMarkerRange.lowerBound]
                    let output = String(decoding: segment, as: UTF8.self)
                    trimBuffer(consumedLocalOffset: legacyMarkerRange.upperBound)
                    return output
                }
            }

            if forciblyClosed || closedStreams >= 2 {
                throw LLDBPersistentSessionError.terminated
            }

            if DispatchTime.now().uptimeNanoseconds >= deadline {
                throw LLDBPersistentSessionError.timeout
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
    }

    private func trimBuffer(consumedLocalOffset: Int) {
        guard consumedLocalOffset > 0 else { return }
        let shouldTrim = consumedLocalOffset > 65_536 || data.count > 524_288
        guard shouldTrim else { return }
        data.removeSubrange(0 ..< consumedLocalOffset)
        baseOffset += consumedLocalOffset
    }
}
