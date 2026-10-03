import Foundation
import SwiftUI

/// Settings → Price alerts: every alert on the account, switched on and off in
/// place (`PATCH /social/alerts/:id`) and swiped away (`DELETE`). New alerts are set
/// from a token's bell, where the price is.
struct AlertsListView: View {
    private let store = PriceAlertStore.shared

    @State private var busyAlertIds: Set<String> = []
    @State private var actionError: String?
    @State private var notificationsDenied = false

    var body: some View {
        List {
            if notificationsDenied {
                Section {
                    Text("Notifications are off for Cooked Paper, so these alerts can't reach you. Turn them on in the Settings app.")
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                }
                .listRowBackground(Color.appSurface)
            }

            if !store.hasLoaded && store.isLoading {
                Section {
                    ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
                }
                .listRowBackground(Color.appSurface)
            } else if !store.hasLoaded, let loadError = store.loadError {
                Section {
                    EmptyStateView(symbol: "wifi.slash", title: "Couldn't load your alerts", detail: loadError) {
                        Task { await store.load() }
                    }
                }
                .listRowBackground(Color.appSurface)
            } else if store.alerts.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "bell",
                        title: "No alerts yet",
                        detail: "Tap the bell on any token to be notified when its price crosses a level."
                    )
                }
                .listRowBackground(Color.appSurface)
            } else {
                Section {
                    ForEach(store.alerts) { alert in
                        PriceAlertRow(
                            alert: alert,
                            isBusy: busyAlertIds.contains(alert.id),
                            onToggle: { isOn in Task { await setActive(alert, isOn) } }
                        )
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { store.alerts[$0] }
                        Task {
                            for alert in doomed { await delete(alert) }
                        }
                    }
                } footer: {
                    if let actionError {
                        Text(actionError)
                            .font(.caption13)
                            .foregroundStyle(Color.negative)
                    } else {
                        Text("Swipe left on an alert to delete it.")
                            .font(.caption13)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .listRowBackground(Color.appSurface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .reservesTabBarSpace()
        .navigationTitle("Price alerts")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load() }
        .task {
            notificationsDenied = await PushRegistrar.shared.notificationsDenied()
            await store.load()
        }
    }

    private func setActive(_ alert: PriceAlert, _ isActive: Bool) async {
        busyAlertIds.insert(alert.id)
        defer { busyAlertIds.remove(alert.id) }
        actionError = nil
        do {
            try await store.setActive(alert, isActive: isActive)
            Haptics.selection()
        } catch {
            Haptics.error()
            actionError = PriceAlertStore.message(for: error)
        }
    }

    private func delete(_ alert: PriceAlert) async {
        busyAlertIds.insert(alert.id)
        defer { busyAlertIds.remove(alert.id) }
        actionError = nil
        do {
            try await store.delete(alert)
            Haptics.success()
        } catch {
            Haptics.error()
            actionError = PriceAlertStore.message(for: error)
        }
    }
}
