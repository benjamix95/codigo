import SwiftUI

// MARK: - Package Manager Panel

/// Pannello per la gestione delle dipendenze SPM.
struct PackageManagerPanel: View {
    @ObservedObject var store: PackageManagerStore

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .onAppear { store.loadDependencies() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Dipendenze SPM")
                .font(.headline)
            Spacer()
            stateIndicator
            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch store.state {
        case .idle:
            EmptyView()
        case .resolving:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Resolving...").font(.caption)
            }
        case .updating:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Updating...").font(.caption)
            }
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button(action: { store.resolve() }) {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .help("Resolve")
            .buttonStyle(.plain)

            Button(action: { store.update() }) {
                Image(systemName: "arrow.up.circle")
            }
            .help("Update")
            .buttonStyle(.plain)

            Button(action: { store.cleanCache() }) {
                Image(systemName: "trash")
            }
            .help("Pulisci Cache")
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.dependencies.isEmpty {
            emptyState
        } else {
            dependencyList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Nessuna dipendenza trovata")
                .font(.headline)
            Text("Aggiungi dipendenze al Package.swift")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dependencyList: some View {
        List(store.dependencies) { dep in
            dependencyRow(dep)
        }
    }

    private func dependencyRow(_ dep: PackageManagerStore.PackageDependency) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: dep.isLocal ? "folder" : "shippingbox")
                    .foregroundColor(dep.isLocal ? .orange : .blue)
                Text(dep.name)
                    .font(.system(.callout, design: .monospaced))
                    .bold()
                Spacer()
                Text(dep.version)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.1))
                    )
            }

            if !dep.url.isEmpty {
                Text(dep.url)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}
