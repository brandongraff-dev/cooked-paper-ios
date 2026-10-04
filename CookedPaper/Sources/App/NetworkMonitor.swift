import Foundation
import Network
import Observation
import SwiftUI

/// Whether the device has a usable network path, from `NWPathMonitor`. Drives the
/// app-wide offline banner; screens keep their own error states for requests that
/// fail anyway (a server being down isn't "offline").
@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// Optimistic until the first path update, so launch never flashes the banner.
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        #if DEBUG
        // Screenshot runs serve every request in-process; the banner would only be
        // noise from the simulator's own network state.
        if MockAPI.isEnabled { return }
        #endif
        // `@Sendable` so the handler runs on the monitor's queue without inheriting
        // this class's main-actor isolation; it hops back with a plain Bool.
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.update(online: online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.cooked.paper.network-monitor"))
    }

    private func update(online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
    }
}

/// The lightweight "you're offline" pill, pinned under the status bar.
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: Space.s8) {
            Image(systemName: "wifi.slash")
                .font(.caption13)
            Text("You're offline. Prices may be out of date.")
                .font(.caption13)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, Space.s16)
        .frame(height: Metrics.chipHeight)
        .background(Color.appSurfaceElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.appSeparator, lineWidth: 1))
        .padding(.horizontal, Space.margin)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offlineBanner")
    }
}
