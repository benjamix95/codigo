import SwiftUI
import CoderEngine
import Foundation

extension SidePanelView {
    var searchPanelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search files...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { performSearch() }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.backgroundSecondary)

            Divider().opacity(0.2)

            if searchResults.isEmpty && !searchQuery.isEmpty {
                VStack(spacing: 6) {
                    Text("No results")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(searchResults.prefix(200).enumerated()), id: \.offset) { _, result in
                            Button {
                                openFilesStore.openFile(result.path)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((result.path as NSString).lastPathComponent)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("L\(result.line): \(result.text)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func performSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let ctx = context else { searchResults = []; return }

        Task {
            var results: [(path: String, line: Int, text: String)] = []
            for root in ctx.folderPaths {
                await searchInDirectory(root, query: q, results: &results, maxResults: 200)
            }
            await MainActor.run { searchResults = results }
        }
    }

    private func searchInDirectory(
        _ dir: String,
        query: String,
        results: inout [(path: String, line: Int, text: String)],
        maxResults: Int
    ) async {
        guard results.count < maxResults else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        let filtered = items.filter { !$0.hasPrefix(".") && !Self.excludedDirs.contains($0) }

        for item in filtered {
            guard results.count < maxResults else { return }
            let path = (dir as NSString).appendingPathComponent(item)
            if isDirectory(path) {
                await searchInDirectory(path, query: query, results: &results, maxResults: maxResults)
            } else {
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                let lines = content.components(separatedBy: .newlines)
                for (i, line) in lines.enumerated() {
                    guard results.count < maxResults else { break }
                    if line.localizedCaseInsensitiveContains(query) {
                        results.append((path: path, line: i + 1, text: line.trimmingCharacters(in: .whitespaces)))
                    }
                }
            }
        }
    }
}
