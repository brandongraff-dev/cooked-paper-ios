import SwiftUI
import UIKit

/// Settings → Streamer mode: the link to a live overlay of your paper portfolio for OBS
/// (or any streaming tool that takes a browser source). Big sells beyond ±20% play a
/// COOKING or COOKED banner on stream. Percentages only, never amounts.
struct StreamerModeView: View {
    @State private var overlay: OverlayKey?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var confirmsRotate = false
    @State private var copied = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Show your paper trades live on stream. Add the link below to OBS as a Browser source (about 600 × 300). It updates every few seconds, and a sell beyond ±20% fires a COOKING or COOKED banner your chat will clip.")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.appSurface)

            Section("Overlay link") {
                if isLoading {
                    ProgressView()
                } else if let url = overlay?.url {
                    Text(url)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("streamer.url")
                    Button(copied ? "Copied" : "Copy link") {
                        UIPasteboard.general.string = url
                        Haptics.success()
                        copied = true
                    }
                    Button("Make a new link", role: .destructive) { confirmsRotate = true }
                } else {
                    Button(isWorking ? "Creating…" : "Create overlay link") {
                        Task { await rotate() }
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("streamer.create")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.negative)
                }
            }
            .listRowBackground(Color.appSurface)

            Section {
                Text("Anyone with this link can see your paper portfolio's returns and recent trades. If it leaks, make a new one: the old link stops working at once.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
            .listRowBackground(Color.appSurface)

            Section("Play with your viewers") {
                NavigationLink {
                    RoomsView()
                } label: {
                    SettingsRow(symbol: "dot.radiowaves.left.and.right", title: "Host a room: Beat the Streamer")
                }
            }
            .listRowBackground(Color.appSurface)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Streamer mode")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Make a new overlay link?", isPresented: $confirmsRotate, titleVisibility: .visible) {
            Button("Make a new link", role: .destructive) { Task { await rotate() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current link stops working. Update the browser source in OBS afterwards.")
        }
    }

    private func load() async {
        do {
            overlay = try await OverlayAPI.current()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func rotate() async {
        isWorking = true
        defer { isWorking = false }
        do {
            overlay = try await OverlayAPI.rotate()
            copied = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
