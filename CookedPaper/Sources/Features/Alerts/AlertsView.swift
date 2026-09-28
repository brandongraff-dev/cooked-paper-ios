import Foundation
import SwiftUI

/// Price-crossing alerts only — the one `AlertRule` kind this app builds
/// (`AlertModels.swift`). Reached from Settings for signed-in accounts.
struct AlertsView: View {
    @State private var alerts: [PriceAlert] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateSheet = false

    private var isGuest: Bool { SessionStore.shared.isGuest }

    var body: some View {
        Group {
            if isGuest {
                EmptyStateView(
                    symbol: "bell.slash",
                    title: "Sign in to set price alerts",
                    detail: "Price alerts are tied to your account, so a guest session can't create or see them."
                )
            } else if isLoading {
                ProgressView()
            } else if let errorMessage {
                EmptyStateView(symbol: "wifi.slash", title: "Couldn't load your alerts", detail: errorMessage)
            } else if alerts.isEmpty {
                EmptyStateView(
                    symbol: "bell",
                    title: "No price alerts yet",
                    detail: "Tap + to get notified when a token crosses a price you pick."
                )
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .reservesTabBarSpace()
        .navigationTitle("Price alerts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !isGuest {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityLabel("Add")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateAlertSheet { created in
                alerts.insert(created, at: 0)
            }
        }
        .task { await load() }
    }

    private var list: some View {
        List {
            ForEach(alerts) { alert in
                AlertRow(alert: alert)
                    .listRowBackground(Color.appSurface)
                    .listRowSeparatorTint(Color.appSeparator)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await delete(alert) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    private func load() async {
        guard !isGuest else { return }
        isLoading = alerts.isEmpty
        errorMessage = nil
        do {
            alerts = try await AlertsAPI.list()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(_ alert: PriceAlert) async {
        let previous = alerts
        alerts.removeAll { $0.id == alert.id }
        do {
            _ = try await AlertsAPI.delete(id: alert.id)
            Haptics.tap()
        } catch {
            alerts = previous
            Haptics.error()
        }
    }
}

private struct AlertRow: View {
    let alert: PriceAlert

    var body: some View {
        switch alert.rule {
        case .priceCrossed(let mint, let direction, let priceUsd):
            ListRow(title: alert.name, subtitle: "\(mint.prefix(4))…\(mint.suffix(4))") {
                TokenAvatar(mint: mint)
            } trailing: {
                Text((direction == .above ? "Above " : "Below ") + PriceFormat.price(priceUsd))
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
            }

        case .unsupported(let kind):
            // Created elsewhere (e.g. the web app) with a rule this app doesn't build
            // or edit. Shown so it isn't silently missing from the list, never as an
            // editable row.
            ListRow(title: alert.name, subtitle: "\u{201c}\(kind)\u{201d} alerts aren\u{2019}t supported here") {
                Circle()
                    .fill(Color.appFill)
                    .frame(width: Metrics.avatar, height: Metrics.avatar)
                    .overlay(Image(systemName: "questionmark").foregroundStyle(Color.textTertiary))
            } trailing: {
                EmptyView()
            }
            .opacity(0.6)
        }
    }
}

private struct CreateAlertSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCreated: (PriceAlert) -> Void

    @State private var mint = ""
    @State private var direction: AlertRule.Direction = .above
    @State private var priceText = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var priceUsd: Decimal? {
        let value = Decimal(string: priceText, locale: Locale.current)
        return (value.map { $0 > 0 } ?? false) ? value : nil
    }

    private var trimmedMint: String {
        mint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool { !trimmedMint.isEmpty && priceUsd != nil }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s24) {
                field("Token mint") {
                    // No search picker in this pass — Discover's token search could
                    // feed this field once alerts get an entry point there.
                    TextField("Mint address", text: $mint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                VStack(alignment: .leading, spacing: Space.s8) {
                    Text("Direction")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                    HStack(spacing: Space.s8) {
                        Chip(title: "Above", isSelected: direction == .above) { direction = .above }
                        Chip(title: "Below", isSelected: direction == .below) { direction = .below }
                    }
                }

                field("Price (USD)") {
                    TextField("0.00", text: $priceText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                }

                Spacer()

                Button {
                    Task { await submit() }
                } label: {
                    if isBusy {
                        ProgressView().tint(Color.inverseText)
                    } else {
                        Text("Create alert")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!canSubmit || isBusy)
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s16)
            .background(Color.appSurfaceElevated)
            .navigationTitle("New price alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text(label)
                .font(.caption13)
                .foregroundStyle(Color.textSecondary)
            content()
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, Space.s16)
                .frame(height: 48)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        }
    }

    private func submit() async {
        guard let priceUsd else { return }
        isBusy = true
        errorMessage = nil
        do {
            let name = "\(direction == .above ? "Above" : "Below") \(PriceFormat.price(priceUsd))"
            let created = try await AlertsAPI.create(
                name: name,
                mint: trimmedMint,
                direction: direction,
                priceUsd: priceUsd
            )
            Haptics.success()
            onCreated(created)
            dismiss()
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }
}
