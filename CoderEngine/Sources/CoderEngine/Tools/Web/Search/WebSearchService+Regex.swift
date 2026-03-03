import Foundation

extension WebSearchService {
    func regexMatches(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        return matches.map { match in
            (0..<match.numberOfRanges).compactMap { i -> String? in
                let range = match.range(at: i)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
        }
    }
}
