import Foundation

extension UnifiedToolRuntime {
    func executeWebSearch(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = (call.args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return failure("query is required", errorCode: "validation", startDate: startDate)
        }

        do {
            let results = try await webSearch.search(query: query, maxResults: 10)
            if results.isEmpty {
                return success([
                    "title": "Web search: \(query)",
                    "query": query,
                    "detail": "No results found",
                    "output": "[]",
                    "resultCount": "0"
                ], startDate: startDate)
            }

            let jsonArray: [[String: String]] = results.map { result in
                ["title": result.title, "snippet": result.snippet, "url": result.url]
            }
            let jsonData = try JSONSerialization.data(withJSONObject: jsonArray, options: [.prettyPrinted, .sortedKeys])
            let output = String(data: jsonData, encoding: .utf8) ?? "[]"

            return success([
                "title": "Web search: \(query)",
                "query": query,
                "detail": "\(results.count) results",
                "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                "resultCount": "\(results.count)"
            ], startDate: startDate)
        } catch {
            return failure(
                "Web search failed: \(error.localizedDescription)",
                errorCode: "transport",
                startDate: startDate,
                payload: ["query": query, "title": "Web search failed"]
            )
        }
    }

    // MARK: - Web Fetch

    func executeWebFetch(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let urlString = (call.args["url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else {
            return failure("url is required", errorCode: "validation", startDate: startDate)
        }

        do {
            let markdown = try await webFetch.fetch(urlString: urlString)
            return success([
                "title": "Fetched: \(urlString)",
                "url": urlString,
                "detail": "\(markdown.count) chars",
                "output": truncate(markdown, maxBytes: context.policy.maxBashOutputBytes)
            ], startDate: startDate)
        } catch {
            return failure(
                "Web fetch failed: \(error.localizedDescription)",
                errorCode: "transport",
                startDate: startDate,
                payload: ["url": urlString, "title": "Web fetch failed"]
            )
        }
    }

    // MARK: - Browser Tools

    func executeBrowserNavigate(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        let url = (call.args["url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            return failure("url is required", errorCode: "validation", startDate: startDate)
        }
        guard isAllowedBrowserURL(url) else {
            return failure(
                "Navigation to localhost or private network addresses is not allowed",
                errorCode: "validation",
                startDate: startDate,
                payload: ["url": url, "title": "Navigation blocked"]
            )
        }
        await bridge.navigate(to: url)
        try? await Task.sleep(for: .milliseconds(500))
        let currentURL = await bridge.getCurrentURL() ?? url
        let title = await bridge.getPageTitle() ?? ""
        return success([
            "title": "Navigated to \(currentURL)",
            "detail": title.isEmpty ? currentURL : "\(title) — \(currentURL)",
            "url": currentURL,
            "output": "Successfully navigated to \(currentURL)\(title.isEmpty ? "" : "\nPage title: \(title)")"
        ], startDate: startDate)
    }

    private func isAllowedBrowserURL(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased() else {
            return false
        }

        if host == "localhost" || host == "::1" || host == "0.0.0.0" {
            return false
        }

        if let ipv4 = parseIPv4(host) {
            let a = ipv4.0
            let b = ipv4.1
            if a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && (16...31).contains(b)) {
                return false
            }
        }

        return true
    }

    private func parseIPv4(_ host: String) -> (Int, Int, Int, Int)? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return nil }
        guard octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return (octets[0], octets[1], octets[2], octets[3])
    }

    func executeBrowserScreenshot(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        guard let pngData = await bridge.takeScreenshot() else {
            return failure("Failed to capture screenshot", errorCode: "runtime", startDate: startDate)
        }
        let base64 = pngData.base64EncodedString()
        let currentURL = await bridge.getCurrentURL() ?? ""
        return success([
            "title": "Screenshot captured",
            "detail": "\(pngData.count / 1024)KB PNG",
            "url": currentURL,
            "output": "data:image/png;base64,\(base64)"
        ], startDate: startDate)
    }

    func executeBrowserConsoleLogs(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        let levelFilter = call.args["level"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastN = Int(call.args["last_n"] ?? "100") ?? 100
        let logs = await bridge.getConsoleLogs(level: levelFilter)
        let lines = logs.split(separator: "\n")
        let recentLogs = lines.suffix(lastN).joined(separator: "\n")
        return success([
            "title": "Console logs",
            "detail": "\(lines.count) entries\(levelFilter.map { " (filter: \($0))" } ?? "")",
            "output": recentLogs.isEmpty ? "(no console logs)" : recentLogs
        ], startDate: startDate)
    }

    func executeBrowserClick(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        let selector = (call.args["selector"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else {
            return failure("selector is required", errorCode: "validation", startDate: startDate)
        }
        let clicked = await bridge.click(selector: selector)
        if clicked {
            return success([
                "title": "Clicked element",
                "detail": selector,
                "output": "Successfully clicked element matching '\(selector)'"
            ], startDate: startDate)
        } else {
            return failure(
                "Element not found: \(selector)",
                errorCode: "not_found",
                startDate: startDate,
                payload: ["title": "Click failed", "detail": selector]
            )
        }
    }

    func executeBrowserType(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        let selector = (call.args["selector"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = call.args["text"] ?? ""
        guard !selector.isEmpty else {
            return failure("selector is required", errorCode: "validation", startDate: startDate)
        }
        let typed = await bridge.type(selector: selector, text: text)
        if typed {
            return success([
                "title": "Typed text",
                "detail": "'\(text.prefix(40))' into \(selector)",
                "output": "Successfully typed text into element matching '\(selector)'"
            ], startDate: startDate)
        } else {
            return failure(
                "Element not found: \(selector)",
                errorCode: "not_found",
                startDate: startDate,
                payload: ["title": "Type failed", "detail": selector]
            )
        }
    }

    func executeBrowserEvaluateJS(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        let script = (call.args["script"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else {
            return failure("script is required", errorCode: "validation", startDate: startDate)
        }
        let result = await bridge.evaluateJS(script)
        return success([
            "title": "Evaluated JS",
            "detail": "\(script.prefix(60))",
            "output": result ?? "undefined"
        ], startDate: startDate)
    }

    func executeBrowserGetContent(call: ToolCall, startDate: Date) async -> ToolResult {
        guard let bridge = browserBridge else {
            return failure("Browser bridge not available", errorCode: "transport", startDate: startDate)
        }
        guard let content = await bridge.getPageContent() else {
            return failure("Failed to get page content", errorCode: "runtime", startDate: startDate)
        }
        let truncated = content.count > 100_000 ? String(content.prefix(100_000)) + "\n... (truncated)" : content
        let currentURL = await bridge.getCurrentURL() ?? ""
        return success([
            "title": "Page content",
            "url": currentURL,
            "detail": "\(content.count) chars",
            "output": truncated
        ], startDate: startDate)
    }
}
