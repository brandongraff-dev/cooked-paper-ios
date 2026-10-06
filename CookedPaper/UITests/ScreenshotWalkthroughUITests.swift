import XCTest

/// UI tests run on XCTest, not Swift Testing — Apple has not shipped Swift Testing
/// support for UI automation, so this is the one place in the app that correctly uses
/// `XCTestCase` instead of `Testing`/`@Test`.
///
/// `nonisolated` on the class itself, not just its methods: the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` globally, which would otherwise make
/// this class (and its inherited initializers) implicitly @MainActor — but
/// `XCTestCase`'s required initializers are `nonisolated`, and a subclass cannot
/// override a nonisolated declaration with an isolated one. Every method that
/// actually touches the UI is still explicitly `@MainActor` below.
///
/// Split into two test methods rather than one long walkthrough, because of a
/// confirmed Xcode/xcodebuild limitation: `xcodebuild test` run from the command
/// line (the only way this project is ever built, there being no Mac in its
/// authoring environment) does not push a StoreKit Configuration to the simulator
/// the way launching from the Xcode IDE does — neither the scheme's "StoreKit
/// Configuration" setting nor `StoreKitTest`'s `SKTestSession` actually reach the
/// launched process under the CLI, so `Product.products(for:)` is reliably empty
/// in CI no matter what this project configures. That's a real, externally-verified
/// tooling gap, not a bug in this app — see the comment on
/// `SubscriptionStore.refreshEntitlement()` for the corresponding app-side escape
/// hatch. Given that, one test walks onboarding through the paywall and stops
/// there (its screenshot of an empty product catalog is the honest CI-environment
/// result, not a failure to hide), and a second test uses that escape hatch to
/// start already "subscribed" and screenshot everything past the paywall instead.
nonisolated final class ScreenshotWalkthroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testOnboardingAndPaywall() throws {
        let app = XCUIApplication()

        // `RootView` gates onboarding on `@AppStorage("hasSeenOnboarding")`; a fresh
        // simulator install has no UserDefaults for this bundle, so onboarding shows
        // on its own. The mock API runs as a brand-new account ($10,000 cash, no
        // positions) so the flow's buys land in a real, changing book.
        app.launchEnvironment["UITEST_MOCK_API"] = "1"
        app.launchEnvironment["UITEST_MOCK_FRESH"] = "1"
        app.launchEnvironment["UITEST_STILL_FRAMES"] = "1"
        app.launch()

        var unreachedSteps: [String] = []

        func tapIfPresent(_ id: String, timeout: TimeInterval = 10) -> Bool {
            let element = app.buttons[id]
            guard element.waitForExistence(timeout: timeout) else {
                unreachedSteps.append("\(id) never appeared")
                return false
            }
            element.tap()
            return true
        }

        if app.buttons["onboarding.balance.continue"].waitForExistence(timeout: 20) {
            Thread.sleep(forTimeInterval: 1.8) // let the balance finish counting up
            attach(app, name: "01-onboarding-balance")
            _ = tapIfPresent("onboarding.balance.continue")
        } else {
            unreachedSteps.append("onboarding balance step never appeared")
        }

        // Practice round: a sped-up replay of real WIF history. Buy, let it run
        // into the rally, then sell.
        if app.buttons["onboarding.practice.buy"].waitForExistence(timeout: 5) {
            Thread.sleep(forTimeInterval: 0.6)
            attach(app, name: "02-onboarding-practice-ready")
            _ = tapIfPresent("onboarding.practice.buy")
            Thread.sleep(forTimeInterval: 8)
            attach(app, name: "02-onboarding-practice-running")
            _ = tapIfPresent("onboarding.practice.sell", timeout: 3)
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "02-onboarding-practice-result")
            _ = tapIfPresent("onboarding.practice.continue")
        } else {
            unreachedSteps.append("practice round never appeared")
        }

        // Onboarding runs as a guest now: straight from the practice round to the
        // questions, with sign-in after the paywall.
        if app.buttons["onboarding.answer.little"].waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 0.6)
            attach(app, name: "02-onboarding-experience")
            _ = tapIfPresent("onboarding.answer.little")
        } else {
            unreachedSteps.append("experience question never appeared")
        }

        if app.buttons["onboarding.goal.learn"].waitForExistence(timeout: 5) {
            Thread.sleep(forTimeInterval: 0.4)
            _ = tapIfPresent("onboarding.goal.learn")
        } else {
            unreachedSteps.append("goal question never appeared")
        }

        if app.buttons["onboarding.coin.0"].waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 0.6)
            attach(app, name: "03-onboarding-pick")
            for index in 0..<3 { _ = tapIfPresent("onboarding.coin.\(index)", timeout: 3) }
            Thread.sleep(forTimeInterval: 0.4)
            attach(app, name: "04-onboarding-picked")
            _ = tapIfPresent("onboarding.buy")
        } else {
            unreachedSteps.append("coin list never appeared")
        }

        let keep = app.buttons["onboarding.keep"]
        if keep.waitForExistence(timeout: 10) {
            // Wait for every fill and a couple of live refreshes so the charts have shape.
            let enabled = NSPredicate(format: "isEnabled == true")
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: keep)], timeout: 20)
            Thread.sleep(forTimeInterval: 7)
            attach(app, name: "05-onboarding-portfolio")
            keep.tap()
        } else {
            unreachedSteps.append("onboarding.keep never appeared")
        }

        // "Save your portfolio": sign-in comes right after the guest portfolio and
        // before the paywall, and claims the guest portfolio. Under the mock the
        // Google button signs straight in (Google's own sheet can't be driven from a
        // test), and the first sign-in of the run is a new account, so username
        // setup follows.
        if app.buttons["signin.google"].waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 0.8)
            attach(app, name: "02-onboarding-signin")
            app.buttons["signin.google"].tap()
        } else {
            unreachedSteps.append("sign-in never appeared after the guest portfolio")
        }

        let subscribeButton = app.buttons["paywall.subscribeButton"]
        let profileContinue = app.buttons["profileSetup.continue"]
        if profileContinue.waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 0.8)
            attach(app, name: "02-onboarding-profile")
            let usernameField = app.textFields["profile.username"]
            if usernameField.waitForExistence(timeout: 3) {
                // Tap the right edge so the cursor lands after the generated handle.
                usernameField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
                usernameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24))
                usernameField.typeText("wifmaxi")
                Thread.sleep(forTimeInterval: 1.2) // debounce + availability check
                attach(app, name: "02-onboarding-profile-picked")
            }
            profileContinue.tap()
            // On to the paywall, now signed in. If saving didn't move on (it
            // shouldn't under the mock), skip rather than stall.
            let skip = app.buttons["profileSetup.skip"]
            if !subscribeButton.waitForExistence(timeout: 5), skip.exists {
                skip.tap()
            }
        } else {
            unreachedSteps.append("profile setup never appeared after a new-account sign-in")
        }

        // No StoreKit Configuration reaches the process under `xcodebuild test`
        // (see the class doc comment), so the plan list can't load here; this
        // screenshot shows the personalized header and the no-plans state.
        if subscribeButton.waitForExistence(timeout: 15) {
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "06-paywall")
        } else {
            unreachedSteps.append("paywall.subscribeButton never appeared")
        }

        if !unreachedSteps.isEmpty {
            XCTFail("Onboarding/paywall walkthrough didn't fully complete: \(unreachedSteps.joined(separator: "; "))")
        }
    }

    @MainActor
    func testMainAppScreenshots() throws {
        let app = XCUIApplication()
        // The DEBUG-only escape hatch in SubscriptionStore.refreshEntitlement() --
        // only this test process ever sets this, so it can't reach a Release build.
        app.launchEnvironment["UITEST_BYPASS_PAYWALL"] = "1"
        // Serve every API call from the in-app demo fixtures (see MockAPI.swift):
        // the production backend isn't reachable from CI, and without this every
        // data-backed screen screenshots as an empty/error state.
        app.launchEnvironment["UITEST_MOCK_API"] = "1"
        // Freezes ambient loops (see AmbientMotion) so the app can go idle between
        // steps and every screenshot is deterministic.
        app.launchEnvironment["UITEST_STILL_FRAMES"] = "1"
        app.launch()

        var unreachedSteps: [String] = []

        let discoverTab = app.buttons["tab.discover"]
        if discoverTab.waitForExistence(timeout: 20) {
            _ = app.buttons["discover.row.0"].waitForExistence(timeout: 10)
            // The demo account has one unseen achievement, celebrated at launch;
            // capture the toast, then let it leave before the Discover screenshot.
            waitOutAchievementToast(app)
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "04-discover")
        } else {
            XCTFail("Main tab bar never appeared within 20s of a bypassed launch.")
            unreachedSteps.append("main tab bar never appeared")
        }

        // From here on, a missing element is treated as a flaky wait rather than a
        // reason to abort: each step screenshots whatever is on screen and moves on
        // to the next one, so one slow call doesn't cost every screenshot after it.
        // Failures are collected and reported together at the end instead, so the
        // test's pass/fail status still reflects what happened.
        let moversChip = app.buttons["Movers"]
        if moversChip.waitForExistence(timeout: 5) {
            moversChip.tap()
            Thread.sleep(forTimeInterval: 0.8)
            attach(app, name: "05-discover-movers")
            app.buttons["Active"].firstMatch.tap()
        } else {
            unreachedSteps.append("Movers feed chip never appeared")
        }

        visitSearch(app, unreachedSteps: &unreachedSteps)
        visitFirstDiscoverRow(app, unreachedSteps: &unreachedSteps)
        visitTab(app, label: "Portfolio", screenshotName: "09-portfolio", unreachedSteps: &unreachedSteps)
        // Best effort: the Cooked meter sheet is a bonus screenshot, so a card that
        // isn't on screen yet is skipped rather than counted as a failure.
        let cookedMeter = app.buttons["portfolio.cookedMeter"]
        if cookedMeter.waitForExistence(timeout: 3), cookedMeter.isHittable {
            cookedMeter.tap()
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "09b-cooked-meter")
            let close = app.buttons["cookedMeter.close"]
            if close.waitForExistence(timeout: 3) { close.tap() } else { app.swipeDown() }
            Thread.sleep(forTimeInterval: 0.8)
        }
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.6)
        attach(app, name: "10-portfolio-scrolled")
        let leveragedRow = app.buttons["portfolio.leveraged.0"]
        if leveragedRow.waitForExistence(timeout: 3) {
            if !leveragedRow.isHittable { app.swipeUp() }
            leveragedRow.tap()
            Thread.sleep(forTimeInterval: 1.2)
            attach(app, name: "10b-leveraged-position")
            let close = app.buttons["Close"].firstMatch
            if close.waitForExistence(timeout: 3) { close.tap() } else { app.swipeDown() }
            Thread.sleep(forTimeInterval: 0.8)
        } else {
            unreachedSteps.append("no leveraged position row in Portfolio")
        }
        visitCompete(app, unreachedSteps: &unreachedSteps)
        visitTab(app, label: "Settings", screenshotName: "12-settings", unreachedSteps: &unreachedSteps)
        visitProfile(app, unreachedSteps: &unreachedSteps)

        if !unreachedSteps.isEmpty {
            XCTFail("Main-app walkthrough didn't fully complete: \(unreachedSteps.joined(separator: "; "))")
        }
    }

    /// The growth features: Beat the Monkey and a top trader's positions on the
    /// Leaderboard; Challenges, event rooms, Squads, Crash Replay and the monthly recap
    /// from Season; and Streamer mode from Settings. Served by MockAPI/MockContests.
    @MainActor
    func testGrowthFeatureScreenshots() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_BYPASS_PAYWALL"] = "1"
        app.launchEnvironment["UITEST_MOCK_API"] = "1"
        app.launchEnvironment["UITEST_STILL_FRAMES"] = "1"
        app.launch()

        var unreached: [String] = []
        guard app.buttons["tab.compete"].waitForExistence(timeout: 20) else {
            XCTFail("Main tab bar never appeared within 20s of a bypassed launch.")
            return
        }
        waitOutAchievementToast(app)
        app.buttons["tab.compete"].tap()
        Thread.sleep(forTimeInterval: 1)

        // Leaderboard: the monkey card, then a trader's (blurred for free) positions.
        let leaderboardSegment = app.buttons["compete.segment.leaderboard"]
        if leaderboardSegment.waitForExistence(timeout: 5) {
            leaderboardSegment.tap()
            Thread.sleep(forTimeInterval: 1.5)
            attach(app, name: "40-leaderboard-beat-the-monkey")
            let row = app.buttons["leaderboard.row.0"]
            if row.waitForExistence(timeout: 5) {
                if !row.isHittable { app.swipeUp() }
                row.tap()
                Thread.sleep(forTimeInterval: 1.5)
                attach(app, name: "41-trader-positions")
                let done = app.buttons["Done"].firstMatch
                if done.waitForExistence(timeout: 3) { done.tap() } else { app.swipeDown() }
                Thread.sleep(forTimeInterval: 1.2)
            } else {
                unreached.append("no leaderboard row")
            }
        } else {
            unreached.append("Leaderboard segment never appeared")
        }

        let seasonSegment = app.buttons["compete.segment.season"]
        guard seasonSegment.waitForExistence(timeout: 5) else {
            XCTFail("Season segment never appeared")
            return
        }
        // The sheet above can still be animating away; retry until Season shows.
        let seasonHeader = app.descendants(matching: .any)["season.header"].firstMatch
        for _ in 0..<3 where !app.buttons["season.challenges"].exists {
            seasonSegment.tap()
            if seasonHeader.waitForExistence(timeout: 5) { break }
        }
        Thread.sleep(forTimeInterval: 1.2)
        attach(app, name: "42-season-new-cards")

        if openFromSeason(app, id: "season.challenges", unreached: &unreached) {
            _ = app.buttons["challenge.start.10k"].waitForExistence(timeout: 5)
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "43-challenges")
            goBack(app)
        }

        if openFromSeason(app, id: "season.rooms", unreached: &unreached) {
            Thread.sleep(forTimeInterval: 1.2)
            attach(app, name: "44-rooms")
            let room = app.buttons["rooms.row.0"].firstMatch
            if room.waitForExistence(timeout: 5) {
                room.tap()
                Thread.sleep(forTimeInterval: 1.5)
                attach(app, name: "45-room-detail")
                goBack(app)
            } else {
                unreached.append("no room row")
            }
            goBack(app)
        }

        if openFromSeason(app, id: "season.squads", unreached: &unreached) {
            Thread.sleep(forTimeInterval: 1.2)
            attach(app, name: "46-squads")
            let squad = app.buttons["squads.row.0"]
            if squad.waitForExistence(timeout: 5) {
                squad.tap()
                Thread.sleep(forTimeInterval: 1.5)
                attach(app, name: "47-squad-detail")
                goBack(app)
            } else {
                unreached.append("no squad row")
            }
            goBack(app)
        }

        if openFromSeason(app, id: "season.replay", unreached: &unreached) {
            Thread.sleep(forTimeInterval: 1.2)
            attach(app, name: "48-crash-replay-list")
            let first = app.buttons["replay.1"]
            if first.waitForExistence(timeout: 5) {
                first.tap()
                let play = app.buttons["replay.play"]
                if play.waitForExistence(timeout: 8) {
                    play.tap()
                    Thread.sleep(forTimeInterval: 3)
                    app.buttons["Buy all"].firstMatch.tap()
                    Thread.sleep(forTimeInterval: 6)
                    app.buttons["Sell 50%"].firstMatch.tap()
                    Thread.sleep(forTimeInterval: 1)
                    attach(app, name: "49-crash-replay-playing")
                    app.buttons["1×"].firstMatch.tap()
                    if app.descendants(matching: .any)["replay.verdict"].firstMatch.waitForExistence(timeout: 60) {
                        Thread.sleep(forTimeInterval: 1.5)
                        attach(app, name: "50-crash-replay-result")
                        let done = app.buttons["Done"].firstMatch
                        if done.waitForExistence(timeout: 3) { done.tap() }
                    } else {
                        unreached.append("replay never reached its verdict")
                        app.buttons["Quit"].firstMatch.tap()
                    }
                    Thread.sleep(forTimeInterval: 1)
                } else {
                    unreached.append("replay player never loaded")
                }
            } else {
                unreached.append("no replay row")
            }
            goBack(app)
        }

        if openFromSeason(app, id: "season.recap", unreached: &unreached) {
            Thread.sleep(forTimeInterval: 1.5)
            attach(app, name: "51-monthly-recap")
            goBack(app)
        }

        let settingsTab = app.buttons["tab.settings"]
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
            let streamer = app.buttons["settings.streamer"]
            if streamer.waitForExistence(timeout: 5) {
                if !streamer.isHittable { app.swipeUp() }
                streamer.tap()
                let create = app.buttons["streamer.create"]
                if create.waitForExistence(timeout: 5) { create.tap() }
                Thread.sleep(forTimeInterval: 1.5)
                attach(app, name: "52-streamer-mode")
            } else {
                unreached.append("no Streamer mode row in Settings")
            }
        }

        if !unreached.isEmpty {
            XCTFail("Growth walkthrough didn't fully complete: \(unreached.joined(separator: "; "))")
        }
    }

    /// Scrolls the Season page until the entry is tappable, then opens it.
    @MainActor
    private func openFromSeason(_ app: XCUIApplication, id: String, unreached: inout [String]) -> Bool {
        let entry = app.buttons[id]
        guard entry.waitForExistence(timeout: 5) else {
            unreached.append("no \(id) on the Season page")
            return false
        }
        var swipes = 0
        while !entry.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        entry.tap()
        return true
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 3) { backButton.tap() }
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Screenshots the launch-time unlock toast if it shows, then waits for it to
    /// go (it dismisses itself after a few seconds).
    @MainActor
    private func waitOutAchievementToast(_ app: XCUIApplication) {
        let toast = app.descendants(matching: .any)["achievement.toast"].firstMatch
        guard toast.waitForExistence(timeout: 4) else { return }
        attach(app, name: "29-achievement-toast")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: toast)
        _ = XCTWaiter.wait(for: [gone], timeout: 10)
    }

    /// Compete: Season, then the Leaderboard and Duels segments, a duel's detail,
    /// Leagues and a league's standings, and the achievements grid (from Season).
    @MainActor
    private func visitCompete(_ app: XCUIApplication, unreachedSteps: inout [String]) {
        let tabButton = app.buttons["tab.compete"]
        guard tabButton.waitForExistence(timeout: 5) else {
            unreachedSteps.append("Compete tab button never appeared")
            attach(app, name: "11-leaderboard")
            return
        }
        tabButton.tap()
        _ = app.descendants(matching: .any)["season.header"].firstMatch.waitForExistence(timeout: 5)
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "30-compete-season")

        let leaderboardSegment = app.buttons["compete.segment.leaderboard"]
        if leaderboardSegment.waitForExistence(timeout: 3) {
            leaderboardSegment.tap()
            Thread.sleep(forTimeInterval: 1.2)
            attach(app, name: "11-leaderboard")
        } else {
            unreachedSteps.append("Leaderboard segment never appeared in Compete")
        }

        let duelsSegment = app.buttons["compete.segment.duels"]
        if duelsSegment.waitForExistence(timeout: 3) {
            duelsSegment.tap()
            _ = app.buttons["duels.active.0"].waitForExistence(timeout: 5)
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "31-compete-duels")
            let activeDuel = app.buttons["duels.active.0"]
            if activeDuel.exists {
                activeDuel.tap()
                _ = app.descendants(matching: .any)["duel.headToHead"].firstMatch.waitForExistence(timeout: 5)
                Thread.sleep(forTimeInterval: 1.2)
                attach(app, name: "32-duel-detail")
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.waitForExistence(timeout: 3) { backButton.tap() }
                Thread.sleep(forTimeInterval: 0.8)
            } else {
                unreachedSteps.append("no active duel row in Duels")
            }
        } else {
            unreachedSteps.append("Duels segment never appeared in Compete")
        }

        let leaguesSegment = app.buttons["compete.segment.leagues"]
        if leaguesSegment.waitForExistence(timeout: 3) {
            leaguesSegment.tap()
            _ = app.buttons["leagues.row.0"].waitForExistence(timeout: 5)
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "34-leagues")
            let firstLeague = app.buttons["leagues.row.0"]
            if firstLeague.exists {
                firstLeague.tap()
                _ = app.descendants(matching: .any)["league.header"].firstMatch.waitForExistence(timeout: 5)
                Thread.sleep(forTimeInterval: 1.2)
                attach(app, name: "35-league-detail")
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.waitForExistence(timeout: 3) { backButton.tap() }
                Thread.sleep(forTimeInterval: 0.8)
            } else {
                unreachedSteps.append("no league row in Leagues")
            }
        } else {
            unreachedSteps.append("Leagues segment never appeared in Compete")
        }

        let seasonSegment = app.buttons["compete.segment.season"]
        if seasonSegment.waitForExistence(timeout: 3) {
            seasonSegment.tap()
            Thread.sleep(forTimeInterval: 0.8)
            let achievementsRow = app.buttons["season.achievements"]
            if achievementsRow.waitForExistence(timeout: 5) {
                // The Daily Call card sits above the season, so the row can be two screens down.
                var swipes = 0
                while !achievementsRow.isHittable && swipes < 3 {
                    app.swipeUp()
                    swipes += 1
                }
                achievementsRow.tap()
                _ = app.descendants(matching: .any)["achievements.cell.first_trade"].firstMatch.waitForExistence(timeout: 5)
                Thread.sleep(forTimeInterval: 1)
                attach(app, name: "33-achievements")
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.waitForExistence(timeout: 3) { backButton.tap() }
                Thread.sleep(forTimeInterval: 0.8)
            } else {
                unreachedSteps.append("no Achievements row on the Season page")
            }
        } else {
            unreachedSteps.append("Season segment never appeared in Compete")
        }
    }

    @MainActor
    private func visitSearch(_ app: XCUIApplication, unreachedSteps: inout [String]) {
        let searchField = app.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 3) else {
            unreachedSteps.append("no search field on Discover")
            return
        }
        searchField.tap()
        searchField.typeText("o")
        Thread.sleep(forTimeInterval: 1.2)
        attach(app, name: "06-discover-search")

        // Back to the feed: clear the query, dismiss the keyboard, leave search mode.
        // iOS versions differ on which of these controls exist, so try each.
        // Delete the query, then press the keyboard's Search/return key (typing a
        // newline does that), which submits and dismisses the keyboard.
        searchField.typeText(XCUIKeyboardKey.delete.rawValue)
        searchField.typeText("\n")
        for label in ["Cancel", "Close"] {
            let button = app.buttons[label].firstMatch
            if button.exists && button.isHittable {
                button.tap()
                break
            }
        }
        Thread.sleep(forTimeInterval: 0.8)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = name
        add(attachment)
    }

    @MainActor
    private func visitFirstDiscoverRow(_ app: XCUIApplication, unreachedSteps: inout [String]) {
        // Discover's feed is a glass panel in a ScrollView, not a List, so its rows
        // are found by their `discover.row.N` identifiers rather than as cells.
        let firstRow = app.buttons["discover.row.0"]
        guard firstRow.waitForExistence(timeout: 10) else {
            unreachedSteps.append("no row in the Discover list to open")
            attach(app, name: "07-token-detail")
            return
        }
        if !firstRow.isHittable { app.swipeUp() }
        firstRow.tap()

        // The nav bar lands before the chart/network calls it triggers finish, so wait
        // a beat past its appearance rather than screenshotting a bare spinner.
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 8)
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, name: "07-token-detail")

        let buyButton = app.buttons["tokenDetail.buy"].firstMatch
        if buyButton.waitForExistence(timeout: 5) {
            buyButton.tap()
            Thread.sleep(forTimeInterval: 1.2)
            attach(app, name: "08-trade-sheet")
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.waitForExistence(timeout: 3) {
                cancel.tap()
            } else {
                app.swipeDown()
            }
            Thread.sleep(forTimeInterval: 0.8)
        } else {
            unreachedSteps.append("no Buy button on the token detail screen")
        }

        visitLeverageSheet(app, unreachedSteps: &unreachedSteps)

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        } else {
            unreachedSteps.append("no back button found on the token detail screen")
        }
    }

    /// Token detail → Leverage: 5x long with $500 of margin, quoted live, then opened.
    @MainActor
    private func visitLeverageSheet(_ app: XCUIApplication, unreachedSteps: inout [String]) {
        let leverageButton = app.buttons["tokenDetail.leverage"].firstMatch
        guard leverageButton.waitForExistence(timeout: 5) else {
            unreachedSteps.append("no Leverage button on the token detail screen")
            return
        }
        leverageButton.tap()
        guard app.buttons["leverage.open"].waitForExistence(timeout: 5) else {
            unreachedSteps.append("leverage sheet never appeared")
            return
        }
        for key in ["5", "0", "0"] { app.buttons[key].firstMatch.tap() }
        Thread.sleep(forTimeInterval: 1.5) // debounce + quote
        attach(app, name: "08b-leverage-sheet")
        app.buttons["leverage.open"].tap()
        if app.buttons["leverage.done"].waitForExistence(timeout: 5) {
            Thread.sleep(forTimeInterval: 0.6)
            attach(app, name: "08c-leverage-opened")
            app.buttons["leverage.done"].tap()
        } else {
            unreachedSteps.append("leverage position never opened")
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists { cancel.tap() }
        }
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Settings → Profile, then its Edit Profile sheet.
    @MainActor
    private func visitProfile(_ app: XCUIApplication, unreachedSteps: inout [String]) {
        // A NavigationLink in a List can surface as a button or a cell, so match
        // the identifier on any element type.
        let profileRow = app.descendants(matching: .any)["settings.profile"].firstMatch
        guard profileRow.waitForExistence(timeout: 5) else {
            unreachedSteps.append("no Profile row in Settings")
            return
        }
        profileRow.tap()
        let edit = app.buttons["profile.edit"]
        guard edit.waitForExistence(timeout: 5) else {
            unreachedSteps.append("profile screen never appeared")
            return
        }
        Thread.sleep(forTimeInterval: 1) // GET /auth/me fills in the join date and referral code
        attach(app, name: "13-profile")
        edit.tap()
        if app.textFields["profile.username"].waitForExistence(timeout: 5) {
            Thread.sleep(forTimeInterval: 0.8)
            attach(app, name: "14-edit-profile")
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.waitForExistence(timeout: 3) { cancel.tap() } else { app.swipeDown() }
            Thread.sleep(forTimeInterval: 0.8)
        } else {
            unreachedSteps.append("edit profile sheet never appeared")
        }
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 3) { backButton.tap() }
    }

    @MainActor
    private func visitTab(
        _ app: XCUIApplication,
        label: String,
        screenshotName: String,
        unreachedSteps: inout [String]
    ) {
        // The app draws its own floating tab bar; its buttons carry `tab.<name>` ids.
        let tabButton = app.buttons["tab.\(label.lowercased())"]
        guard tabButton.waitForExistence(timeout: 5) else {
            unreachedSteps.append("\(label) tab button never appeared")
            attach(app, name: screenshotName)
            return
        }
        tabButton.tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: screenshotName)
    }
}
