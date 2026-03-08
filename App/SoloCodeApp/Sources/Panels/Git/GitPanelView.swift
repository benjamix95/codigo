import SwiftUI
import CoderEngine

struct GitPanelView: View {
    @ObservedObject var store: GitPanelStore
    @EnvironmentObject var providerRegistry: ProviderRegistry
    let effectiveContext: EffectiveContext
    let onOpenFile: (String) -> Void

    @State var expandedSection: GitPanelSection = .changedFiles
    @State var branchSegment: BranchSegment = .local

    enum GitPanelSection: String, CaseIterable {
        case changedFiles = "Changes"
        case commitHistory = "History"
        case branches = "Branches"
        case stash = "Stash"
    }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().opacity(0.4)
            actionBar
            Divider().opacity(0.4)
            segmentPicker
            Divider().opacity(0.4)
            panelContent
            Divider().opacity(0.4)
            commitSection
        }
        .frame(maxWidth: .infinity)
        .background(DesignSystem.Colors.backgroundPrimary)
        .sidebarPanel(cornerRadius: 14)
        .onAppear {
            store.refresh(workingDirectory: effectiveContext.primaryPath)
        }
        .alert("Delete branch?", isPresented: $store.showDeleteBranchConfirm) {
            Button("Cancel", role: .cancel) {
                store.branchToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let name = store.branchToDelete {
                    store.deleteBranch(name: name, force: false)
                }
            }
            Button("Force Delete", role: .destructive) {
                if let name = store.branchToDelete {
                    store.deleteBranch(name: name, force: true)
                }
            }
        } message: {
            Text("Delete branch \"\(store.branchToDelete ?? "")\"?")
        }
    }
}
