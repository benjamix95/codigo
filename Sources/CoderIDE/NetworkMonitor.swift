import Foundation
import Network
import SwiftUI

// MARK: - Connection State

enum ConnectionStatus: Equatable {
    case connected
    case disconnected
    case reconnecting(attempt: Int, maxAttempts: Int)
    case failed(message: String)

    var isOnline: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Network Monitor

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var status: ConnectionStatus = .connected
    @Published private(set) var isPathSatisfied: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "codigo.network-monitor", qos: .utility)
    private var reconnectTask: Task<Void, Never>?

    static let maxReconnectAttempts = 5
    private static let baseDelay: TimeInterval = 2.0

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
        reconnectTask?.cancel()
    }

    private func handlePathUpdate(_ path: NWPath) {
        let wasSatisfied = isPathSatisfied
        isPathSatisfied = path.status == .satisfied

        if isPathSatisfied {
            reconnectTask?.cancel()
            reconnectTask = nil
            status = .connected
        } else if wasSatisfied {
            beginReconnecting()
        }
    }

    private func beginReconnecting() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }

            for attempt in 1...Self.maxReconnectAttempts {
                guard !Task.isCancelled else { return }

                self.status = .reconnecting(attempt: attempt, maxAttempts: Self.maxReconnectAttempts)

                let delay = Self.baseDelay * pow(1.5, Double(attempt - 1))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                guard !Task.isCancelled else { return }

                if self.isPathSatisfied {
                    self.status = .connected
                    return
                }
            }

            guard !Task.isCancelled else { return }
            self.status = .failed(
                message: "Unable to connect after \(Self.maxReconnectAttempts) attempts. Check your internet connection and try again."
            )
        }
    }

    func retryConnection() {
        guard case .failed = status else { return }
        if isPathSatisfied {
            status = .connected
        } else {
            beginReconnecting()
        }
    }
}

// MARK: - Connection Status Banner

struct ConnectionStatusBanner: View {
    @ObservedObject var monitor: NetworkMonitor

    @State private var isVisible = false
    @State private var dismissedFailed = false

    var body: some View {
        Group {
            switch monitor.status {
            case .connected:
                if isVisible {
                    restoredBanner
                }
            case .disconnected:
                EmptyView()
            case .reconnecting(let attempt, let max):
                reconnectingBanner(attempt: attempt, maxAttempts: max)
            case .failed(let message):
                if !dismissedFailed {
                    failedBanner(message: message)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: monitor.status)
        .onChange(of: monitor.status) { _, newValue in
            switch newValue {
            case .reconnecting:
                dismissedFailed = false
                isVisible = true
            case .connected where isVisible:
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { isVisible = false }
                }
            case .failed:
                dismissedFailed = false
                isVisible = true
            default:
                break
            }
        }
    }

    private func reconnectingBanner(attempt: Int, maxAttempts: Int) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(DesignSystem.Colors.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Reconnecting…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                HStack(spacing: 6) {
                    Text("Attempt \(attempt) of \(maxAttempts)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    attemptDots(current: attempt, total: maxAttempts)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DesignSystem.Colors.warning.opacity(0.08))
        .overlay(alignment: .bottom) {
            reconnectProgress(attempt: attempt, maxAttempts: maxAttempts)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func attemptDots(current: Int, total: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...total, id: \.self) { i in
                Circle()
                    .fill(
                        i < current
                        ? DesignSystem.Colors.error.opacity(0.6)
                        : (i == current ? DesignSystem.Colors.warning : DesignSystem.Colors.textTertiary.opacity(0.3))
                    )
                    .frame(width: 5, height: 5)
                    .scaleEffect(i == current ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: current)
            }
        }
    }

    private func reconnectProgress(attempt: Int, maxAttempts: Int) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(DesignSystem.Colors.warning.opacity(0.4))
                .frame(width: geo.size.width * CGFloat(attempt) / CGFloat(maxAttempts), height: 2)
                .animation(.easeInOut(duration: 0.4), value: attempt)
        }
        .frame(height: 2)
    }

    private func failedBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.error.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.error)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Failed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    withAnimation { dismissedFailed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            Button {
                monitor.retryConnection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Try Again")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(DesignSystem.Colors.error, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(DesignSystem.Colors.error.opacity(0.06))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignSystem.Colors.error.opacity(0.3))
                .frame(height: 2)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var restoredBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.success)

            Text("Connection restored")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.success)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DesignSystem.Colors.success.opacity(0.08))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
