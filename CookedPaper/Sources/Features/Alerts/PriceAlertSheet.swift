import Foundation
import SwiftUI

/// The token screen's bell: set a price alert on this token and see or remove the
/// ones already set. The price starts at the current price; whether the alert
/// watches for a rise or a fall follows from the target being above or below it.
struct PriceAlertSheet: View {
    let mint: String
    let symbol: String
    /// Live when the sheet opened; nil if the token has no price (then the person
    /// picks the direction themselves).
    let currentPrice: Decimal?

    @Environment(\.dismiss) private var dismiss
    private let store = PriceAlertStore.shared

    @State private var priceText = ""
    @State private var manualDirection: PriceAlertDirection = .above
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var notificationsDenied = false
    @State private var busyAlertIds: Set<String> = []
    @FocusState private var isPriceFocused: Bool

    static let quickOffsets = [10, 25, -10, -25]

    private var target: Decimal? { PriceAlertMath.parse(priceText) }

    /// Above or below, from the target against the current price. Nil while the
    /// target is missing or equal to the current price (nothing to cross).
    private var direction: PriceAlertDirection? {
        guard let target else { return nil }
        guard let currentPrice, currentPrice > 0 else { return manualDirection }
        if target > currentPrice { return .above }
        if target < currentPrice { return .below }
        return nil
    }

    private var tokenAlerts: [PriceAlert] { store.priceAlerts(for: mint) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s24) {
                    newAlertCard
                    createButton
                    existingAlerts
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.s8)
                .padding(.bottom, Space.s24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appSurfaceElevated)
            .navigationTitle("\(symbol) alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
        .presentationDragIndicator(.visible)
        .onAppear {
            if priceText.isEmpty, let currentPrice, currentPrice > 0 {
                priceText = PriceAlertMath.plain(currentPrice)
            }
        }
        .task {
            notificationsDenied = await PushRegistrar.shared.notificationsDenied()
            await store.loadIfNeeded()
        }
    }

    // MARK: - New alert

    private var newAlertCard: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(spacing: Space.s8) {
                Text("$")
                    .font(.rowValue)
                    .foregroundStyle(Color.textSecondary)
                TextField("Target price", text: $priceText)
                    .font(.rowValue)
                    .keyboardType(.decimalPad)
                    .focused($isPriceFocused)
                    .accessibilityIdentifier("priceAlert.price")
            }
            .padding(.horizontal, Space.s16)
            .frame(height: Metrics.buttonHeight)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))

            if let currentPrice, currentPrice > 0 {
                HStack(spacing: Space.s8) {
                    ForEach(Self.quickOffsets, id: \.self) { percent in
                        Chip(title: percent > 0 ? "+\(percent)%" : "\(PriceFormat.minus)\(abs(percent))%", isSelected: false) {
                            priceText = PriceAlertMath.plain(PriceAlertMath.offset(currentPrice, percent: percent))
                        }
                        .accessibilityIdentifier("priceAlert.offset.\(percent)")
                    }
                }
            } else {
                HStack(spacing: Space.s4) {
                    ForEach(PriceAlertDirection.allCases) { option in
                        Segment(title: option.title, isSelected: manualDirection == option) { manualDirection = option }
                    }
                }
                .padding(Space.s4)
                .background(Color.appSurface, in: Capsule())
            }

            Text(summary)
                .font(.caption13)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: String {
        let now = currentPrice.flatMap { price -> String? in
            price > 0 ? "Now \(PriceFormat.price(price))." : nil
        } ?? ""
        guard let target else { return "Enter the price to be alerted at. \(now)" }
        guard let direction else { return "Pick a price above or below the current one. \(now)" }
        return "Notifies you when \(symbol) \(direction.verb) \(PriceFormat.price(target)). \(now)"
    }

    private var createButtonTitle: String {
        guard let target, let direction else { return "Create alert" }
        return "Alert me \(direction == .above ? "above" : "below") \(PriceFormat.price(target))"
    }

    private var createButton: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Button {
                Task { await create() }
            } label: {
                if isSaving {
                    ProgressView().tint(Color.inverseText)
                } else {
                    Text(createButtonTitle)
                }
            }
            .buttonStyle(.primary)
            .disabled(direction == nil || isSaving)
            .accessibilityIdentifier("priceAlert.create")

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption13)
                    .foregroundStyle(Color.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if notificationsDenied {
                Text("Notifications are off for Cooked Paper, so alerts can't reach you. Turn them on in the Settings app.")
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Existing alerts

    @ViewBuilder
    private var existingAlerts: some View {
        if !tokenAlerts.isEmpty {
            VStack(alignment: .leading, spacing: Space.headerGap) {
                SectionHeader(title: "Your \(symbol) alerts")
                VStack(spacing: 0) {
                    ForEach(Array(tokenAlerts.enumerated()), id: \.element.id) { index, alert in
                        PriceAlertRow(alert: alert, isBusy: busyAlertIds.contains(alert.id), onDelete: {
                            Task { await delete(alert) }
                        })
                        .padding(.horizontal, Space.s16)
                        if index < tokenAlerts.count - 1 {
                            RowSeparator(leadingInset: Space.s16)
                        }
                    }
                }
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        } else if let loadError = store.loadError, !store.hasLoaded {
            HStack(spacing: Space.s8) {
                Text("Couldn't load your alerts. \(loadError)")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s8)
                Button("Retry") { Task { await store.load() } }
                    .buttonStyle(.compact)
            }
        }
    }

    // MARK: - Actions

    private func create() async {
        guard let target, let direction else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await store.createPriceAlert(mint: mint, symbol: symbol, direction: direction, price: target)
            Haptics.success()
            isPriceFocused = false
            // The moment notifications obviously matter: ask now, not at launch.
            await PushRegistrar.shared.requestPermissionIfNeeded()
            notificationsDenied = await PushRegistrar.shared.notificationsDenied()
        } catch {
            Haptics.error()
            errorMessage = PriceAlertStore.message(for: error)
        }
    }

    private func delete(_ alert: PriceAlert) async {
        busyAlertIds.insert(alert.id)
        defer { busyAlertIds.remove(alert.id) }
        do {
            try await store.delete(alert)
            Haptics.success()
        } catch {
            Haptics.error()
            errorMessage = PriceAlertStore.message(for: error)
        }
    }
}

/// One alert: its level and direction, whether it's on, and when it last fired.
struct PriceAlertRow: View {
    let alert: PriceAlert
    var isBusy = false
    var onDelete: (() -> Void)? = nil
    /// Shows an on/off switch (Settings' list) instead of the delete button.
    var onToggle: ((Bool) -> Void)? = nil

    private var title: String {
        guard alert.isPriceAlert, let price = alert.rule.priceUsd, let direction = alert.rule.priceDirection else {
            return alert.name
        }
        return "\(direction.title) \(PriceFormat.price(price))"
    }

    private var subtitle: String {
        var parts = [alert.isActive ? "On" : "Paused"]
        if let fired = alert.lastFiredDate {
            parts.append("last fired \(fired.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Space.s12) {
            Image(systemName: alert.rule.priceDirection == .below ? "arrow.down.right" : "arrow.up.right")
                .font(.body)
                .foregroundStyle(alert.isActive ? Color.textPrimary : Color.textTertiary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rowTitle)
                    .foregroundStyle(alert.isActive ? Color.textPrimary : Color.textSecondary)
                Text(subtitle)
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: Space.s8)
            if isBusy {
                ProgressView()
            } else if let onToggle {
                Toggle("Alert on", isOn: Binding(get: { alert.isActive }, set: { onToggle($0) }))
                    .labelsHidden()
                    .tint(Color.positive)
            } else if let onDelete {
                Button {
                    Haptics.tap()
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Delete alert")
            }
        }
        .padding(.vertical, Space.s4)
    }
}
