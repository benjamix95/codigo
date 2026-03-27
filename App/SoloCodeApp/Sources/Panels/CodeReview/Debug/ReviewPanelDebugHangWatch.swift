import Foundation

/// Probe main-thread backlog e (DEBUG) cattura `sample` del PID quando la review resta attiva a lungo.
@MainActor
enum ReviewPanelDebugHangWatch {
    /// Lettura da `Task.detached`; deve restare accessibile senza MainActor (Swift 6).
    private static let sampleOutputPath = "/Users/benjaminstoica/SoloCode/.cursor/debug-7e54b6-sample.txt"
    private static var probeTasks: [Task<Void, Never>] = []

    static func cancelProbes() {
        probeTasks.forEach { $0.cancel() }
        probeTasks.removeAll()
    }

    /// Differenza tra enqueue su main e esecuzione: se alta, il RunLoop è congestionato.
    static func pokeMainAsyncLatency(label: String, hypothesisId: String = "H_main_lag") {
        #if DEBUG
        let t0 = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.main.async {
            let t1 = DispatchTime.now().uptimeNanoseconds
            let lagMs = Double(t1 &- t0) / 1_000_000.0
            if lagMs > 32 {
                ReviewPanelDebugNDJSON.emit(
                    hypothesisId: hypothesisId,
                    location: "ReviewPanelDebugHangWatch.pokeMainAsyncLatency",
                    message: "main_queue_backlog",
                    data: [
                        "label": label,
                        "lagMs": Int(lagMs),
                        "pid": ProcessInfo.processInfo.processIdentifier,
                    ]
                )
            }
        }
        #endif
    }

    /// Schedula log NDJSON a 5s / 15s e, se la review è ancora attiva, esegue `sample` una volta per finestra.
    static func armForReviewPanel(store: CodeReviewPanelStore) {
        #if DEBUG
        cancelProbes()
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        probeTasks.append(Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await Self.emitProbe(
                store: store,
                pid: pid,
                elapsedLabel: "5s",
                hypothesisId: "H_hang_t5"
            )
        })
        probeTasks.append(Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await Self.emitProbe(
                store: store,
                pid: pid,
                elapsedLabel: "15s",
                hypothesisId: "H_hang_t15"
            )
        })
        #endif
    }

    static func logFindingsTabSurface(store: CodeReviewPanelStore) {
        #if DEBUG
        ReviewPanelDebugNDJSON.emit(
            hypothesisId: "H_ui_findings",
            location: "ReviewPanelFindingsTab.onAppear",
            message: "findings_surface",
            data: [
                "selectedTab": store.selectedTab.rawValue,
                "hasPipelineCard": store.currentPipelineJobState != nil,
                "hasCurrentSnapshot": store.currentSnapshot != nil,
                "selectedSessionId": store.selectedSessionId ?? "",
                "preparing": store.isReviewLaunchPreparing,
                "isRunning": store.isRunning,
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
            ]
        )
        #endif
    }

    #if DEBUG
    private static func emitProbe(
        store: CodeReviewPanelStore,
        pid: Int,
        elapsedLabel: String,
        hypothesisId: String
    ) async {
        let active = store.isReviewLaunchPreparing || store.isRunning
        ReviewPanelDebugNDJSON.emit(
            hypothesisId: hypothesisId,
            location: "ReviewPanelDebugHangWatch.emitProbe",
            message: "review_still_active_probe",
            data: [
                "elapsed": elapsedLabel,
                "pid": pid,
                "active": active,
                "preparing": store.isReviewLaunchPreparing,
                "isRunning": store.isRunning,
                "tab": store.selectedTab.rawValue,
                "selectedSessionId": store.selectedSessionId ?? "",
                "hasSnapshot": store.currentSnapshot != nil,
                "hasPipeline": store.currentPipelineJobState != nil,
            ]
        )
        if active {
            let out = await runSample(pid: pid, seconds: 4)
            ReviewPanelDebugNDJSON.emit(
                hypothesisId: hypothesisId,
                location: "ReviewPanelDebugHangWatch",
                message: "sample_finished",
                data: [
                    "outputPath": out ?? "(failed)",
                    "cliHint": "sample \(pid) 8 -file ~/SoloCode_sample_manual.txt",
                ]
            )
            if let out {
                print("[ReviewPanelDEBUG] sample written: \(out)")
            }
        }
    }

    private nonisolated static func runSample(pid: Int, seconds: UInt32) async -> String? {
        await Task.detached(priority: .utility) {
            let out = await sampleOutputPath
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            p.arguments = ["\(pid)", "\(seconds)", "-file", out]
            do {
                try p.run()
                p.waitUntilExit()
                return p.terminationStatus == 0 ? out : nil
            } catch {
                return nil
            }
        }.value
    }
    #endif
}
