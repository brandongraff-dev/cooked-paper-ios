import Foundation
import SwiftUI

/// Price-crossing alerts only — the one `AlertRule` kind this app builds
/// (`AlertModels.swift`). Not yet reachable from any tab or nav link; a separate
/// integration pass wires an entry point to this screen once concurrent work lands.
struct AlertsView: View {
    @State private var alerts: [PriceAlert] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var animatedRowIDs: Set<String> = []

    private var isGuest: Bool { SessionStore.shared.isGuest }

    var body: some View {
        ZStack {
            AmbientBackground(colors: [CookedColor.Brand.dangerFill, CookedColor.Prism.amber, CookedColor.Prism.indigo], intensity: 0.8)

            if isGuest {
                EmptyStateView(
                    symbol: "bell.slash",
                    title: "Sign in to set price alerts",
                    detail: "Price alerts are tied to your account, so a guest session can't create or see them."
                )
            } else if isLoading {
                ProgressView().tint(CookedColor.Brand.fill)
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
        .navigationTitle("Price Alerts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !isGuest {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
            ForEach(Array(alerts.enumerated()), id: \.element.id) { index, alert in
                AlertRow(alert: alert)
                    .listRowBackground(Rectangle().fill(.ultraThinMaterial))
                    .listRowSeparatorTint(CookedColor.Terminal.border)
                    .staggeredEntrance(index: index, id: alert.id, animatedIDs: $animatedRowIDs)
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
            HStack(spacing: CookedSpacing.sm) {
                TokenLogo(mint: mint, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.name)
                        .font(CookedFont.headline())
                        .foregroundStyle(CookedColor.Terminal.textPrimary)
                        .lineLimit(1)
                    Text(mint)
                        .font(CookedFont.caption())
                        .foregroundStyle(CookedColor.Terminal.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: direction == .above ? "arrow.up" : "arrow.down")
                        .font(.system(size: CookedIconSize.xs, weight: .semibold))
                        .foregroundStyle(CookedColor.Terminal.textSecondary)
                    Text(priceUsd.usdString(fractionDigits: priceUsd < 1 ? 6 : 2))
                        .font(CookedFont.priceMedium())
                        .foregroundStyle(CookedColor.Terminal.textPrimary)
                }
            }
            .padding(.vertical, 4)

        case .unsupported(let kind):
            // Created elsewhere (e.g. the web app) with a rule this app doesn't build
            // or edit. Shown so it isn't silently missing from the list, never as an
            // editable row.
            HStack(spacing: CookedSpacing.sm) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: CookedIconSize.md))
                    .foregroundStyle(CookedColor.Terminal.textMuted)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.name)
                        .font(CookedFont.headline())
                        .foregroundStyle(CookedColor.Terminal.textMuted)
                        .lineLimit(1)
                    Text("Alert kind \u{201c}\(kind)\u{201d} isn\u{2019}t supported here")
                        .font(CookedFont.caption())
                        .foregroundStyle(CookedColor.Terminal.textMuted)
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .opacity(0.5)
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
            ZStack {
                CookedColor.Terminal.bgBase.ignoresSafeArea()

                VStack(alignment: .leading, spacing: CookedSpacing.lg) {
                    VStack(alignment: .leading, spacing: CookedSpacing.xs) {
                        Text("Token mint")
                            .font(CookedFont.caption())
                            .foregroundStyle(CookedColor.Terminal.textMuted)
                        // No search picker in this pass — Discover's token search
                        // could feed this field once alerts get an entry point there.
                        TextField("Mint address", text: $mint)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(CookedSpacing.sm)
                            .background(CookedColor.Terminal.bgSurfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: CookedRadius.sm, style: .continuous))
                            .foregroundStyle(CookedColor.Terminal.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: CookedSpacing.xs) {
                        Text("Direction")
                            .font(CookedFont.caption())
                            .foregroundStyle(CookedColor.Terminal.textMuted)
                        HStack(spacing: CookedSpacing.xs) {
                            CookedChip(title: "Above", isSelected: direction == .above) {
                                direction = .above
                            }
                            CookedChip(title: "Below", isSelected: direction == .below) {
                                direction = .below
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: CookedSpacing.xs) {
                        Text("Price (USD)")
                            .font(CookedFont.caption())
                            .foregroundStyle(CookedColor.Terminal.textMuted)
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .padding(CookedSpacing.sm)
                            .background(CookedColor.Terminal.bgSurfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: CookedRadius.sm, style: .continuous))
                            .foregroundStyle(CookedColor.Terminal.textPrimary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(CookedFont.caption())
                            .foregroundStyle(CookedColor.Terminal.sell)
                    }

                    Spacer()

                    Button {
                        Task { await submit() }
                    } label: {
                        if isBusy {
                            ProgressView().tint(CookedColor.Brand.onFill)
                        } else {
                            Text("Create alert")
                        }
                    }
                    .buttonStyle(.cookedPrimary(enabled: canSubmit))
                    .disabled(!canSubmit || isBusy)
                }
                .padding(CookedSpacing.lg)
            }
            .navigationTitle("New Price Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(CookedColor.Terminal.bgBase)
    }

    private func submit() async {
        guard let priceUsd else { return }
        isBusy = true
        errorMessage = nil
        do {
            let name = "\(direction == .above ? "Above" : "Below") \(priceUsd.usdString(fractionDigits: priceUsd < 1 ? 6 : 2))"
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
