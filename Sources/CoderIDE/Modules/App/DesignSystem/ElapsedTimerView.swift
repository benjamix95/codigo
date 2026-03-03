import Combine
import SwiftUI

struct ElapsedTimerView<Content: View>: View {
    let startDate: Date
    let updateInterval: TimeInterval
    let content: (Int) -> Content

    @State private var now: Date = Date()
    private let ticker: Publishers.Autoconnect<Timer.TimerPublisher>

    init(
        startDate: Date,
        updateInterval: TimeInterval = 1.0,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.startDate = startDate
        self.updateInterval = updateInterval
        self.content = content

        let tolerance = min(0.25, updateInterval * 0.25)
        self.ticker = Timer.publish(
            every: updateInterval,
            tolerance: tolerance,
            on: .main,
            in: .common
        ).autoconnect()
    }

    var body: some View {
        content(elapsedSeconds)
            .onAppear {
                now = Date()
            }
            .onReceive(ticker) { date in
                now = date
            }
    }

    private var elapsedSeconds: Int {
        max(0, Int(now.timeIntervalSince(startDate)))
    }
}
