import Foundation
import Observation

/// The account's achievements, and the queue of unlocks waiting to be celebrated.
///
/// Unlocks are decided on the server only. They reach the app two ways: live, as
/// `paper:achievement` on the `/paper` socket (`receive(_:)`), and on every return
/// to the foreground, when `checkForUnseen()` fetches the list and celebrates any
/// unlock still marked `seen: false` (one that landed while the app was closed).
/// Each celebrated unlock is reported back with `POST /paper/achievements/seen`, so
/// it is celebrated once per account, not once per launch.
@Observable
@MainActor
final class AchievementCenter {
    static let shared = AchievementCenter()

    private(set) var response: AchievementsResponse?
    private(set) var isLoading = false
    /// The server has no achievements route (404): the feature hides itself.
    private(set) var isUnavailable = false
    private(set) var errorMessage: String?
    /// The unlock on screen right now (`AchievementToast`).
    private(set) var celebrating: Achievement?

    @ObservationIgnored private var queue: [Achievement] = []
    @ObservationIgnored private var celebratedIds: Set<String> = []
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var isChecking = false

    private init() {}

    var achievements: [Achievement] { response?.achievements ?? [] }
    var unlockedCount: Int { response?.unlockedCount ?? achievements.filter(\.unlocked).count }
    var total: Int { response?.total ?? achievements.count }

    /// Loads (or reloads) the list for the achievements screens.
    func load() async {
        guard SessionStore.shared.isSignedIn else { return }
        isLoading = response == nil
        errorMessage = nil
        do {
            response = try await AchievementsAPI.list()
            isUnavailable = false
        } catch let error where error.isNotFound {
            isUnavailable = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// On launch and each return to the foreground: celebrate anything unlocked
    /// since the last look. Quiet on every failure.
    func checkForUnseen() async {
        guard SessionStore.shared.isSignedIn, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let fresh = try await AchievementsAPI.list()
            response = fresh
            isUnavailable = false
            let unseen = fresh.achievements.filter { $0.unlocked && $0.seen == false }
            // Oldest first, so a backlog plays in the order it was earned.
            for achievement in unseen.reversed() {
                enqueue(achievement)
            }
        } catch let error where error.isNotFound {
            isUnavailable = true
        } catch {
            // Offline or a server hiccup: the next foreground tries again.
        }
    }

    /// A live `paper:achievement`.
    func receive(_ achievement: Achievement) {
        merge(achievement)
        guard achievement.unlocked else { return }
        enqueue(achievement)
    }

    /// The toast was tapped, swiped or timed out.
    func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        celebrating = nil
        showNextIfIdle()
    }

    func signedOut() {
        response = nil
        queue = []
        celebratedIds = []
        dismissTask?.cancel()
        dismissTask = nil
        celebrating = nil
    }

    // MARK: - Queue

    private func enqueue(_ achievement: Achievement) {
        guard !celebratedIds.contains(achievement.id) else { return }
        celebratedIds.insert(achievement.id)
        queue.append(achievement)
        markSeen([achievement.id])
        showNextIfIdle()
    }

    private func showNextIfIdle() {
        guard celebrating == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        celebrating = next
        Haptics.success()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            self?.dismissCurrent()
        }
    }

    private func markSeen(_ ids: [String]) {
        Task {
            try? await AchievementsAPI.markSeen(ids: ids)
        }
    }

    /// Folds a single updated achievement into the loaded list.
    private func merge(_ achievement: Achievement) {
        guard let current = response else { return }
        var list = current.achievements
        let wasUnlocked = list.first { $0.id == achievement.id }?.unlocked ?? false
        if let index = list.firstIndex(where: { $0.id == achievement.id }) {
            list.remove(at: index)
        }
        // Unlocked first, newest first — the server's own order.
        if achievement.unlocked {
            list.insert(achievement, at: 0)
        } else {
            list.append(achievement)
        }
        let count = current.unlockedCount + (achievement.unlocked && !wasUnlocked ? 1 : 0)
        response = AchievementsResponse(achievements: list, unlockedCount: count, total: current.total)
    }
}
