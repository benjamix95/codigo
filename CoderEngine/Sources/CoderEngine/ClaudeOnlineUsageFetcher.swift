import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClaudeOnlineUsageFetcher {
    public static func fetch(adminApiKey: String, now: Date = Date()) async -> ClaudeUsage? {
        let key = adminApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        guard var components = URLComponents(
            string: "https://api.anthropic.com/v1/organizations/usage_report/claude_code"
        ) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: isoDateUTC(now)),
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "order", value: "desc")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return parseUsage(json)
        } catch {
            return nil
        }
    }

    private static func parseUsage(_ root: [String: Any]) -> ClaudeUsage? {
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheWriteTokens = 0
        var totalCostUSD = 0.0
        var sawAnything = false

        func parseTokenDict(_ dict: [String: Any]) {
            inputTokens += number(dict["input_tokens"])
            outputTokens += number(dict["output_tokens"])
            cacheReadTokens += number(dict["cache_read_input_tokens"]) + number(dict["cache_read_tokens"])
            cacheWriteTokens += number(dict["cache_creation_input_tokens"]) + number(dict["cache_write_tokens"])
            if !dict.isEmpty {
                sawAnything = true
            }
        }

        func parseEstimatedCost(_ dict: [String: Any]) {
            let amount = numberDouble(dict["amount"])
            if amount > 0 {
                // Anthropic usage report returns amount in minor units (e.g. cents).
                totalCostUSD += amount / 100.0
                sawAnything = true
            }
        }

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let tokens = dict["tokens"] as? [String: Any] {
                    parseTokenDict(tokens)
                }
                if let estimated = dict["estimated_cost"] as? [String: Any] {
                    parseEstimatedCost(estimated)
                }

                // Fallback for flattened payload variants.
                parseTokenDict(dict)
                totalCostUSD += numberDouble(dict["total_cost_usd"])
                totalCostUSD += numberDouble(dict["cost_usd"])

                for value in dict.values {
                    walk(value)
                }
                return
            }
            if let array = node as? [Any] {
                for item in array {
                    walk(item)
                }
            }
        }

        if let data = root["data"] {
            walk(data)
        } else {
            walk(root)
        }

        guard sawAnything else { return nil }
        let costString: String? = totalCostUSD > 0 ? String(format: "$%.4f", totalCostUSD) : nil
        return ClaudeUsage(
            sessionCost: costString,
            inputTokens: inputTokens > 0 ? inputTokens : nil,
            outputTokens: outputTokens > 0 ? outputTokens : nil,
            cacheReadTokens: cacheReadTokens > 0 ? cacheReadTokens : nil,
            cacheWriteTokens: cacheWriteTokens > 0 ? cacheWriteTokens : nil,
            totalDuration: nil,
            source: "online"
        )
    }

    private static func isoDateUTC(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let start = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }

    private static func number(_ value: Any?) -> Int {
        if let n = value as? NSNumber {
            return n.intValue
        }
        if let s = value as? String {
            return Int(s) ?? 0
        }
        return 0
    }

    private static func numberDouble(_ value: Any?) -> Double {
        if let n = value as? NSNumber {
            return n.doubleValue
        }
        if let s = value as? String {
            return Double(s) ?? 0
        }
        return 0
    }
}
