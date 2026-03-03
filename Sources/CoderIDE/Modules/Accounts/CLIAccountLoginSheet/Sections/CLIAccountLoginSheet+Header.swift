import SwiftUI

extension CLIAccountLoginSheet {
    // MARK: - Header
    var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(providerColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: providerIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(providerColor)
            }

            Text("Sign in to \(account.provider.displayName)")
                .font(.title3.weight(.semibold))

            Text(account.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
