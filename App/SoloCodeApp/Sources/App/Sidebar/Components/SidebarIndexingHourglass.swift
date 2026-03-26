import SwiftUI

/// Clessidra animata: resta in piedi qualche secondo → si capovolge (180°) → pausa → torna dritta → ripete.
struct SidebarIndexingHourglass: View {
    @State private var rotationDegrees: Double = 0
    @State private var loopTask: Task<Void, Never>?

    /// Attesa prima del primo capovolgimento e dopo essere tornati dritti.
    private static let pauseUprightNs: UInt64 = 2_200_000_000
    /// Attesa mentre la clessidra sta “sopra” (capovolta).
    private static let pauseInvertedNs: UInt64 = 2_800_000_000
    private static let flipDuration: TimeInterval = 0.55

    var body: some View {
        Image(systemName: "hourglass")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.orange)
            .rotationEffect(.degrees(rotationDegrees))
            .onAppear(perform: startFlipLoop)
            .onDisappear(perform: stopFlipLoop)
            .accessibilityHidden(true)
    }

    private func startFlipLoop() {
        stopFlipLoop()
        loopTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pauseUprightNs)
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: Self.flipDuration)) {
                        rotationDegrees = 180
                    }
                }
                try? await Task.sleep(nanoseconds: Self.pauseInvertedNs)
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: Self.flipDuration)) {
                        rotationDegrees = 0
                    }
                }
            }
        }
    }

    private func stopFlipLoop() {
        loopTask?.cancel()
        loopTask = nil
    }
}
