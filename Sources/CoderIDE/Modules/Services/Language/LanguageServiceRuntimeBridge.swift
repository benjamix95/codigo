import CoderEngine
import Foundation

actor LanguageServiceRuntimeBridge: RuntimeLanguageService {
    private let service: LanguageService

    init(service: LanguageService) {
        self.service = service
    }

    func goToDefinition(symbol: String, fileHint: String?) async throws -> [RuntimeLanguageLocation] {
        let locations = try await service.goToDefinition(symbol: symbol, fileHint: fileHint)
        return locations.map(Self.mapLocation)
    }

    func findReferences(symbol: String, limit: Int) async throws -> [RuntimeLanguageLocation] {
        let locations = try await service.findReferences(symbol: symbol, limit: limit)
        return locations.map(Self.mapLocation)
    }

    func rename(oldName: String, newName: String) async throws -> RuntimeLanguageRenamePlan {
        let plan = try await service.rename(oldName: oldName, newName: newName)
        return RuntimeLanguageRenamePlan(
            oldName: plan.oldName,
            newName: plan.newName,
            references: plan.references.map(Self.mapLocation),
            source: Self.mapSource(plan.source)
        )
    }

    private static func mapLocation(_ location: LanguageLocation) -> RuntimeLanguageLocation {
        RuntimeLanguageLocation(
            filePath: location.filePath,
            line: location.line,
            column: location.column,
            symbolName: location.symbolName,
            source: mapSource(location.source)
        )
    }

    private static func mapSource(_ source: LanguageServiceSource) -> RuntimeLanguageSource {
        switch source {
        case .sourceKitLSP:
            return .sourceKitLSP
        case .localIndex:
            return .localIndex
        }
    }
}
