import Foundation

extension CodebaseIndex {
    /// Incremental indexing: re-indexes only modified files.
    public func incrementalUpdate() async -> IndexResult {
        var transaction = beginIndexingTransaction(operationName: "incrementalUpdate")
        let startTime = transaction.startedAt
        Self.logger.info("incrementalUpdate: starting")
        defer { finishIndexingTransaction(transaction) }

        refreshGitignoreRules()
        rebuildWorkspaceFileTrees()

        let sourceNodes = allFileNodes.filter { _, node in
            node.isSourceFile
                && node.size <= Self.maxFileSize
                && !isFileExcluded(node.relativePath)
                && !isGitignored(node.relativePath, isDirectory: false)
        }

        let currentSourcePaths = Set(sourceNodes.keys)
        let indexedPaths = Set(indexedFiles.keys)
        let removedPaths = indexedPaths.subtracting(currentSourcePaths)

        let totalToProcess = max(1, sourceNodes.count + removedPaths.count + 1) // + semantic phase
        var processed = 0
        var removedCount = 0
        _indexingProgress = (current: 0, total: totalToProcess)

        for relativePath in removedPaths.sorted() {
            if Task.isCancelled {
                return makeCurrentIndexResult(
                    durationMs: Int(Date().timeIntervalSince(startTime) * 1000),
                    updatedFiles: removedCount
                )
            }
            removeIndexedFile(relativePath)
            removedCount += 1
            processed += 1
            _indexingProgress = (current: processed, total: totalToProcess)
        }

        let pipelineResult = await runIncrementalReindexPipeline(
            sourceNodes: sourceNodes,
            startingProcessed: processed,
            totalToProcess: totalToProcess
        )
        if pipelineResult.wasCancelled {
            return makeCurrentIndexResult(
                durationMs: Int(Date().timeIntervalSince(startTime) * 1000),
                updatedFiles: removedCount + pipelineResult.updatedCount
            )
        }

        // Re-build import graph
        buildImportGraph()
        _indexingProgress = (current: max(0, totalToProcess - 1), total: totalToProcess)

        // Update semantic index incrementally (not a full rebuild)
        if let firstRoot = currentWorkspacePaths.first {
            if !pipelineResult.changedFiles.isEmpty {
                await semanticIndex.incrementalUpdate(
                    changedFiles: pipelineResult.changedFiles,
                    workspaceRoot: firstRoot
                )
            }
            for relativePath in removedPaths {
                await semanticIndex.removeFile(relativePath)
            }
            for relativePath in pipelineResult.failedReindexPaths {
                await semanticIndex.removeFile(relativePath)
            }
        } else if !pipelineResult.changedFiles.isEmpty || removedCount > 0 {
            await semanticIndex.clear()
        }
        _indexingProgress = (current: totalToProcess, total: totalToProcess)

        isWorkspaceRebuildInProgress = false
        await flushQueuedRealtimeChanges()

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        indexDurationMs = durationMs
        _indexingProgress = nil
        _status = .ready
        transaction.markCompleted()

        Self.logger.info(
            "incrementalUpdate: completed — \(pipelineResult.updatedCount) updated, \(removedCount) removed, \(durationMs)ms"
        )
        let totalFilesCount = allFileNodes.values.reduce(into: 0) { count, node in
            if node.kind == .file { count += 1 }
        }

        return IndexResult(
            totalFiles: totalFilesCount,
            totalSourceFiles: indexedFiles.count,
            totalSymbols: totalSymbolsExtracted,
            totalDirectories: fileTrees.values.reduce(0) { acc, tree in
                acc + countDirectories(tree)
            },
            durationMs: durationMs,
            languages: languageBreakdown(),
            updatedFiles: pipelineResult.updatedCount + removedCount
        )
    }
}
