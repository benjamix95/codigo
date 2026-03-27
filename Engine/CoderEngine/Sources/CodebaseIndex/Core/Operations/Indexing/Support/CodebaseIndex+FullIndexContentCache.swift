import Foundation

extension CodebaseIndex {
    func indexFilesInParallel(batch: ArraySlice<FileNode>) async -> [IndexedFile] {
        await withTaskGroup(of: IndexedFile?.self, returning: [IndexedFile].self) { group in
            for node in batch {
                group.addTask {
                    SymbolExtractor.indexFile(
                        absolutePath: node.absolutePath,
                        relativePath: node.relativePath,
                        language: node.language
                    )
                }
            }

            var collected: [IndexedFile] = []
            for await result in group {
                if let indexed = result {
                    collected.append(indexed)
                }
            }
            return collected
        }
    }

    struct IndexedBatchWithContent {
        let indexedFiles: [IndexedFile]
        let contentByAbsolutePath: [String: String]
    }

    func indexFilesInParallelWithContent(batch: ArraySlice<FileNode>) async -> IndexedBatchWithContent {
        await withTaskGroup(of: (IndexedFile, String)?.self, returning: IndexedBatchWithContent.self) { group in
            for node in batch {
                group.addTask {
                    guard let read = SymbolExtractor.indexFileWithContent(
                        absolutePath: node.absolutePath,
                        relativePath: node.relativePath,
                        language: node.language
                    ) else {
                        return nil
                    }
                    return (read.file, read.content)
                }
            }

            var indexedFiles: [IndexedFile] = []
            var contentByAbsolutePath: [String: String] = [:]
            for await result in group {
                guard let result else { continue }
                indexedFiles.append(result.0)
                contentByAbsolutePath[result.0.absolutePath] = result.1
            }
            return IndexedBatchWithContent(
                indexedFiles: indexedFiles,
                contentByAbsolutePath: contentByAbsolutePath
            )
        }
    }

    func buildSemanticContentCache(
        for indexedFiles: [IndexedFile],
        seededByAbsolutePath seeded: [String: String]
    ) async -> [String: String] {
        var contentByAbsolutePath = seeded
        let missing = indexedFiles.filter { contentByAbsolutePath[$0.absolutePath] == nil }
        guard !missing.isEmpty else { return contentByAbsolutePath }

        let loaded = await withTaskGroup(of: (String, String)?.self, returning: [String: String].self) { group in
            for indexed in missing {
                let absolutePath = indexed.absolutePath
                group.addTask {
                    guard let content = SemanticIndex.readTextFile(at: absolutePath) else {
                        return nil
                    }
                    return (absolutePath, content)
                }
            }

            var output: [String: String] = [:]
            for await result in group {
                guard let result else { continue }
                output[result.0] = result.1
            }
            return output
        }
        contentByAbsolutePath.merge(loaded) { current, _ in current }
        return contentByAbsolutePath
    }
}
