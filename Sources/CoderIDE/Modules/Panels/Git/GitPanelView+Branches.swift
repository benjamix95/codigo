import SwiftUI

extension GitPanelView {
    enum BranchSegment: String, CaseIterable { case local = "Local", remote = "Remote" }

    // MARK: - Branches

    var branchesSection: some View {
        VStack(spacing: 0) {
            // Search + segment
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField("Search branches...", text: $store.branchSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Local/Remote picker
            Picker("", selection: $branchSegment) {
                ForEach(BranchSegment.allCases, id: \.self) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            if branchSegment == .local {
                localBranchesContent
            } else {
                remoteBranchesContent
            }

            Divider().opacity(0.3).padding(.horizontal, 8)

            // Create new branch
            Button {
                store.newBranchName = store.branchSearch.trimmingCharacters(in: .whitespacesAndNewlines)
                store.showCreateBranch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.agentColor)
                    Text("New branch")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(store.gitRoot == nil || store.isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $store.showCreateBranch) {
            createBranchSheet
        }
    }

    private var localBranchesContent: some View {
        Group {
            if store.filteredBranches.isEmpty {
                Text("No branches found")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.filteredBranches) { branch in
                            localBranchRow(branch)
                        }
                    }
                }
            }
        }
    }

    private func localBranchRow(_ branch: GitBranch) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(branch.isCurrent ? DesignSystem.Colors.agentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(branch.name)
                    .font(.system(size: 12, weight: branch.isCurrent ? .bold : .medium))
                    .foregroundStyle(.primary)
                if branch.isCurrent, let st = store.status, st.changedFiles > 0 {
                    Text("\(st.changedFiles) uncommitted")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if branch.isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.agentColor)
            } else {
                // Delete button
                Button {
                    store.branchToDelete = branch.name
                    store.showDeleteBranchConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.error.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Delete branch")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if !branch.isCurrent && !store.isBusy {
                store.switchBranch(branch.name)
            }
        }
        .hoverHighlight(Color.primary.opacity(0.04))
    }

    private var remoteBranchesContent: some View {
        Group {
            let query = store.branchSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let filtered = query.isEmpty ? store.remoteBranches : store.remoteBranches.filter { $0.name.lowercased().contains(query) }
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Text("No remote branches")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    if store.remoteBranches.isEmpty {
                        Button("Fetch remotes") { store.fetch() }
                            .font(.system(size: 11, weight: .semibold))
                            .disabled(store.isBusy)
                    }
                }
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { branch in
                            remoteBranchRow(branch)
                        }
                    }
                }
            }
        }
    }

    private func remoteBranchRow(_ branch: GitBranch) -> some View {
        Button {
            store.checkoutRemoteBranch(name: branch.name)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(branch.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy)
        .hoverHighlight(Color.primary.opacity(0.04))
    }

    private var createBranchSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create & checkout new branch")
                .font(.system(size: 15, weight: .semibold))
            TextField("Branch name", text: $store.newBranchName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    store.showCreateBranch = false
                }
                Button("Create") {
                    store.createAndCheckoutBranch()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    store.newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || store.isBusy)
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}

