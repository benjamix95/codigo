import Foundation

struct CodeReviewStreamTextAccumulator {
    private var chunks: [String] = []

    mutating func consume(_ event: StreamEvent) {
        switch event {
        case .textDelta(let delta):
            chunks.append(delta)
        case .textReplace(let replacement):
            chunks = [replacement]
        default:
            break
        }
    }

    var text: String {
        chunks.joined()
    }
}
