import Foundation

// MARK: - Web Fetch

/// Fetches a web page and converts its HTML content to clean Markdown.
public actor WebFetchService {
    private let maxContentBytes: Int = 131_072  // 128KB
    private let maxOutputChars: Int = 12_000
    private let fetchTimeoutSeconds: TimeInterval = 30

    public init() {}

    /// Fetch a URL and return its content as Markdown.
    public func fetch(urlString: String) async throws -> String {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw WebToolsError.invalidURL(urlString)
        }

        // Prepend https:// if no protocol
        if !normalized.contains("://") {
            normalized = "https://" + normalized
        }

        guard let url = URL(string: normalized) else {
            throw WebToolsError.invalidURL(normalized)
        }

        // Block localhost / private IPs
        if let host = url.host?.lowercased() {
            if isBlockedHost(host) {
                throw WebToolsError.invalidURL("Cannot fetch localhost or private network addresses")
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = fetchTimeoutSeconds

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = fetchTimeoutSeconds
        config.timeoutIntervalForResource = fetchTimeoutSeconds + 10
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (data, response, wasDownloadTruncated) = try await fetchDataWithLimit(
            session: session,
            request: request,
            maxBytes: maxContentBytes
        )
        guard let http = response as? HTTPURLResponse else {
            throw WebToolsError.searchFailed("Invalid HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw WebToolsError.httpError(http.statusCode)
        }

        // Detect content type — only process text/HTML
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let isHTML = contentType.contains("text/html") || contentType.contains("application/xhtml")
        let isText = contentType.contains("text/") || contentType.contains("application/json") || contentType.contains("application/xml")

        guard isHTML || isText || contentType.isEmpty else {
            throw WebToolsError.decodingFailed
        }

        // Detect encoding from Content-Type header
        let encoding = detectEncoding(from: contentType) ?? .utf8
        guard let rawContent = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii) else {
            throw WebToolsError.decodingFailed
        }

        // Convert HTML → Markdown (or return raw text for non-HTML)
        let markdown: String
        if isHTML || contentType.isEmpty {
            markdown = HTMLToMarkdown.convert(rawContent)
        } else {
            markdown = rawContent
        }

        var output = markdown
        var notes: [String] = []

        // Truncate output
        if output.count > maxOutputChars {
            output = String(output.prefix(maxOutputChars))
            notes.append("...[content truncated at \(maxOutputChars) chars]")
        }
        if wasDownloadTruncated {
            notes.append("...[download truncated at \(maxContentBytes) bytes]")
        }

        if !notes.isEmpty {
            output += "\n\n" + notes.joined(separator: "\n")
        }
        return output
    }

    private func detectEncoding(from contentType: String) -> String.Encoding? {
        let lower = contentType.lowercased()
        if lower.contains("charset=utf-8") { return .utf8 }
        if lower.contains("charset=iso-8859-1") || lower.contains("charset=latin1") { return .isoLatin1 }
        if lower.contains("charset=ascii") { return .ascii }
        if lower.contains("charset=windows-1252") { return .windowsCP1252 }
        return nil
    }

    private func fetchDataWithLimit(
        session: URLSession,
        request: URLRequest,
        maxBytes: Int
    ) async throws -> (Data, URLResponse, Bool) {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }

        var collected = Data()
        collected.reserveCapacity(min(maxBytes, 32_768))

        var iterator = bytes.makeAsyncIterator()
        while let byte = try await iterator.next() {
            if collected.count >= maxBytes {
                return (collected, response, true)
            }
            collected.append(byte)
        }
        return (collected, response, false)
    }
}
