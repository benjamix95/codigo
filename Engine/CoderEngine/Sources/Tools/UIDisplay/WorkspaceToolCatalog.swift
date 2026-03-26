import Foundation

/// API pubblica per sapere se un nome tool appartiene al catalogo workspace SoloCode (per badge UI, ecc.).
public enum WorkspaceToolCatalog {
    public static func isWorkspaceTool(_ raw: String) -> Bool {
        ProviderToolEventMapper.isWorkspaceCatalogTool(raw)
    }
}
