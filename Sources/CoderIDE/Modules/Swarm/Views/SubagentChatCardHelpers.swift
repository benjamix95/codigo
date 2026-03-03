import SwiftUI

enum SubagentChatCardHelpers {
    static func roleDisplayName(from swarmId: String) -> String {
        let id = swarmId
        if let dashRange = id.range(of: "-", options: .backwards),
           id[dashRange.upperBound...].count <= 10,
           id[dashRange.upperBound...].allSatisfy({ $0.isHexDigit || $0.isLetter }) {
            return String(id[..<dashRange.lowerBound]).capitalized
        }
        return id
    }
}
