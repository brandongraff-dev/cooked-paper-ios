# Cooked Paper (iOS)

A native SwiftUI, **paper-trading-only** companion to Cooked (cooked.trade). You trade
simulated money against real Solana token prices, play against other people, and climb
monthly seasons. No real money is ever involved. It talks to the same `apps/api`
backend as the web and Expo apps (`https://api.cooked.trade`).

- iPhone only, portrait only, dark UI only. Deployment target **iOS 17**, Swift 6.
- Free to start. **Pro** is $49.99/year (7-day free trial) or $12.99/month. See
  "Subscriptions".
- Dependencies: `socket.io-client-swift` (16.1+) and `GoogleSignIn-iOS` (9.0+). Nothing else.
- CI builds on a macOS runner with Xcode 26 on every push. The sources use no
  iOS 26-only APIs.

## How the app works

**First run.** Balance ($10,000 paper) → a practice round that replays real WIF/USDT
1-minute closes from 19 Mar 2024 → two questions (experience: Never / A little / A lot;
goal: Learn / Test / Compete) → pick up to three coins, which are bought as real paper
trades → your live portfolio → "Save your portfolio" sign-in → username (new accounts) →
the paywall (closable, "Start free") → the app.

Everything before sign-in runs as a **guest paper session**: `POST /paper/portfolios/starter`
with no `Authorization` mints a 7-day guest token kept in the Keychain. Signing in claims
it (`POST /paper/portfolios/claim`), so the onboarding positions carry over. The first
screen has "Already have an account? Sign in". If the server refuses guests, sign-in
moves to right after the practice round.

**Navigation.** A custom floating capsule tab bar with four icon-only tabs (titles are
accessibility labels), hidden while the keyboard is up:

| Tab | What's in it |
|---|---|
| Discover | Token search and five feeds |
| Portfolio | Stats, positions, recently closed, Cooked meter, leveraged positions |
| Compete | Season · Duels · Leagues · Leaderboard, plus play modes |
| Settings | Account, price alerts, streamer mode, subscription, legal, sign out |

**Discover.** Search ("Search tokens", 300 ms debounce) and feed chips: Active, Movers,
New, Popular, Held. Refreshes every 30 s while visible and on foreground.

**Token detail.**
- Ranges LIVE, 1H, 1D, 1W, 1M, ALL, with a line/candles toggle. Candles have a
  long-press-then-drag crosshair (a bare drag would steal page scrolling).
- LIVE streams trade by trade from the `/market` socket (1 s REST polling as fallback)
  and plays the tape back slightly behind the server clock so the line moves smoothly.
  Fills never use the delayed price. Other ranges refetch in place (1H every 15 s, 1D 30 s,
  1W 60 s, 1M/ALL 120 s) and the header price is live on every range.
- Your own trades appear as +/− markers; price-alert levels are drawn on the chart.
- Stats (market cap, liquidity, 24h volume, 24h change) and "Your position" (value,
  quantity, average cost, return, share button). Bell sets a price alert (Pro).
- Bottom bar: Sell (if you hold it), Leverage (Pro), Buy.

**Trading.** Quick amounts 25 / 50 / 75 / Max. Buys are a percentage of cash sent as
`notionalUsd`; sells use the server's `sellPercent`. Each order carries an idempotent
`clientOrderId` and is quoted first (`/paper/portfolios/:id/quote`).

**Leverage (Pro).** Multiples, directions and minimum margin come from
`GET /paper/leverage/config` (fallback 2×/5×/10×, long and short). Entry, size and
liquidation price come from a server quote. The sheet states the liquidation move and
that the most you can lose is your margin. Positions show P&L on margin, liquidation price
and distance to it; closing past liquidation settles as "Liquidated". The server can refuse
(Solana tokens only, thin or unknown liquidity, too close to liquidation, position limit,
below minimum margin, price moved) and the app shows the reason.

**Cooked meter.** An on-device 0–100 "how cooked is your portfolio" score from liquidation
proximity (0–35), leverage exposure (0–15), concentration (0–25), drawdown (0–15) and thin
liquidity (0–10). No positions is 0; negative equity with positions open is 100. For fun,
not advice.

**Compete.**
- *Season*: a UTC calendar month ranked on main-portfolio return (duels don't count). Shows
  tier, rank, return, distance to the next tier, the tier ladder, top 10, past seasons and
  your monthly recap. Hosts the Daily Call, the Crowd record and a grid of play modes.
- *Daily Call*: one featured token per UTC day; call Higher or Lower. Locks 20:00 UTC,
  settles 00:00 UTC. A correct call extends a streak; shows the crowd split and yesterday's
  result. Streak share card.
- *Crowd record*: how often the Daily Call majority was right recently (up to 14 days) and
  how fading it would have gone. Hidden until enough days are counted.
- *Duels*: two players, a fresh $1,000 portfolio each, best return wins; 1h, 24h or 7d; by
  username or open invite link. Accept, decline, cancel, rematch. Trades use the duel's own
  portfolio. Result share card.
- *Leagues*: private leaderboards by invite code, ranked on season return. Owners rename,
  rotate the code, remove members, delete; members leave.
- *Squads*: 3–5 friends share one portfolio; every trade is a proposal the members vote on,
  and it runs on a majority yes.
- *Live Rooms*: market-event rooms (CPI day, a Fed decision) anyone can join, or host your own
  ("Beat the Streamer"). Fixed window, fresh $10,000 each, board freezes at the end.
- *Prop Challenges*: pick a balance tier and try to reach +8% before equity touches −5%
  within 30 days; the server judges it. Free accounts get one attempt a month.
- *Crash Replay*: replay real historical crashes blind, an hour of candles at a time, then see
  SURVIVED or COOKED against buy-and-hold. Scenario 1 is free; the rest are Pro. A 15-second
  720×1280 clip can be exported and shared.
- *Recap*: monthly recap (this month and the five before) with trader type, return, best and
  worst trade and Daily Call record, as a 9:16 story card.
- *Achievements*: a catalog with progress. The server decides unlocks; a toast appears live
  (`paper:achievement`) and on foreground for anything unseen.
- *Leaderboard*: windows 24h / 7d / 30d / This month, a top-3 podium, a pinned "your spot"
  card, refresh every 60 s. Tapping a trader shows their positions (shares and returns only);
  free users see it blurred behind the paywall.

Everything in Compete is paper money; screens say results are simulated. A feature whose
backend route returns 404 hides itself (Daily Call and Crowd record do this).

**Profile and Settings.** Profile: avatar, name, @handle, referral code and "Invite friends",
achievements preview. Settings: account, Price alerts, Streamer mode, Manage subscription,
Restore purchases, Terms and Privacy links, Sign out, Delete account (App Store 5.1.1(v)),
Reset portfolio. *Streamer mode* creates an overlay link for OBS (Browser source, 600×300);
a ±20% sell fires a COOKING / COOKED banner showing percentages only.

**Price alerts and push.** Alerts use `/social/alerts` with `price_crossed` rules (push
channel, 5-minute cooldown); the token screen's bell prefills the price with ±10/25% chips.
Notification permission is requested at a moment of intent (creating an alert, or after a
trade, via a soft ask first), never at launch. The APNs token is sent to
`POST /social/apns-tokens` (sandbox for Debug, production for Release) and revoked on sign-out.
Push payload keys `mint`, `duelId`, `leagueId`, `achievementId` open the matching screen. The
server refuses token registration until an APNs key is configured, which the app treats as a
silent no-op.

**Share cards** are drawn on device with `ImageRenderer`: 1080×1350 PNG (trade, duel result,
Daily Call streak, crowd record, achievement) and 1080×1920 story cards (recap), plus the
replay video clip. Footer: "Paper money. Results simulated. cooked.trade". Sells and closes
also offer the server-rendered link card (`/cards/meta/…`, percentages only), hidden if the
endpoint doesn't answer.

**Review prompt.** After a profitable spot sell or leveraged close, at most once per 90 days,
signed-in accounts only, never after a loss.

**Offline.** A banner appears app-wide while the device is offline.

**Deep links.** Custom scheme `cookedpaper://`: `token/<mint>`, `duel/<code>`,
`duel-id/<id>`, `league/<code>`, `league-id/<id>`, `achievements`. Universal links:
`https://cooked.trade/d/<code>` (duel invite) and `/l/<code>` (league invite), also on
`www.cooked.trade`. Squads, rooms, challenges and replays have no deep link.

## Principles the code follows

- **Money is `Decimal`, never `Double`**, decoded from the API's decimal-string fields with
  `@DecimalString` / `@OptionalDecimalString` (`Models/DecimalCodable.swift`).
- **Null means "unmeasured", never zero.** Missing values render as "—".
- **The live socket implements the server's resume protocol**: it tracks the last `seq` per
  portfolio, resumes with `sinceSeq`, treats a `counterReset`/`truncated` gap as a fresh
  baseline, and a heartbeat watchdog reconnects on silence. Both sockets re-read the access
  token before each reconnect and refresh the session if the handshake is refused.
- **One iPhone per account.** Signing in on a new iPhone ends the old phone's session
  (`session_evicted`); that phone returns to sign-in with a note. The website isn't counted.
- **No wallet login and no real trading** in this app.

## Subscriptions

Defined in `Sources/Paywall/` and enforced **on the device** with StoreKit 2; the API has no
paywall by design, so a modified client could bypass the free-tier limits.

- **Products** (`ProductID`): `app.cooked.paper.annual` ($49.99/yr, 7-day free trial, the
  default and a computed "save N%" badge), `app.cooked.paper.monthly` ($12.99/mo, no trial),
  `app.cooked.paper.annual.offer` ($29.99/yr, one-time offer), and `app.cooked.paper.weekly`,
  which is only recognised so earlier weekly subscribers keep access and is **not sold** (the
  paywall lists annual and monthly only). Prices live in App Store Connect; the local
  `StoreKit/Products.storekit` mirrors them and still contains the weekly product
  ($3.99, 3-day trial) for local testing.
- **Free tier** (`FreeTier.swift`): full access for the first 3 days from account creation,
  then 3 buys per day in the main portfolio. Selling is never limited; duel and contest trades
  don't count. The count comes from the server's trade history, so reinstalling doesn't reset it.
- **Pro-only:** leverage, price alerts, other traders' positions, Crash Replay scenarios 2+,
  and unlimited Prop Challenge attempts.
- **Paywall triggers:** after onboarding, when the day's buys run out, once when full access
  ends, after a profitable sell, and when a Pro feature is opened.
- **One-time offer:** closing the onboarding paywall without buying shows the $29.99/yr
  offer once per device with the regular price struck through; no timer. If StoreKit returns
  no offer product the paywall just closes.
- **Trial UX:** "Start 7-day free trial", a how-it-works timeline, a soft reminder ask, and a
  local reminder two days before the trial converts.
- **Server sync:** every verified transaction's JWS goes to `POST /billing/apple/transactions`
  and `GET /billing/apple/entitlement` is read back; purchases carry `appAccountToken` = the
  account UUID. You're subscribed if StoreKit **or** the server says so; an unreachable
  server never removes a StoreKit entitlement. Set `POST /billing/apple/notifications` as the
  App Store Server Notifications URL in App Store Connect.
- **Funnel:** `Funnel.swift` posts named steps (app opened, onboarding started/completed,
  paywall shown/closed, trial started, subscribed, offer shown, upsell tapped, first trade)
  to `POST /events` with a random per-install id, never the IDFA, so no ATT prompt.

Before the app ever goes free, remember that annual plans can outlast the paid era; plan
that with a lawyer.

## Project layout

```
CookedPaper/
  project.yml           XcodeGen spec: the source of truth (.xcodeproj is gitignored)
  Sources/
    App/                Entry point, root gate (onboarding/sign-in/paywall), tab shell,
                        deep links, push, stores (portfolio, duels, leagues), achievements,
                        review prompt, network monitor
    DesignSystem/       Tokens ported from packages/config/design-tokens.ts, components,
                        haptics, share-card renderer
    Networking/         APIClient, Keychain/session storage, per-area API files (Auth, Paper,
                        Token, Leaderboard, Social, Billing, Cards, Compete), /paper and
                        /market sockets, Funnel, and the DEBUG-only mock API
    Models/             Codable models and the Decimal wrappers
    Paywall/            SubscriptionStore, FreeTier, PaywallView, one-time offer
    Features/           Auth, Onboarding, Discover, TokenDetail, Trade, Leverage, Alerts,
                        Portfolio, Compete, Replay, Leaderboard, Profile, Settings
  Resources/            Info.plist, entitlements, PrivacyInfo.xcprivacy, assets,
                        PracticeReplay.json
  Scripts/              GenerateIcon.swift, attach-storekit-to-test-action.py
  StoreKit/             Products.storekit (local testing)
  Tests/                Swift Testing unit tests: decimals, deep links, trade math, Cooked
                        meter, market playback, share-card formatting, model decoding
  UITests/              Screenshot walkthrough plus chart and trade recordings
.github/workflows/ios-build-and-screenshot.yml
screenshots/            Older walkthrough PNGs (onboarding to price alerts); they predate
                        Compete and are regenerated by CI
```

## First-time setup

1. `brew install xcodegen`, then from `CookedPaper`: `xcodegen generate` and
   `open CookedPaper.xcodeproj`.
2. **Signing (owner-provided).** `DEVELOPMENT_TEAM` in `project.yml` is empty; set your Team
   ID. CI builds with `CODE_SIGNING_ALLOWED=NO`. Bundle id is `app.cooked.paper`. Enable Sign
   in with Apple, Push Notifications and Associated Domains on the App ID. `aps-environment`
   comes from `APS_ENVIRONMENT` (`development` for Debug, `production` for Release).
3. **Google sign-in.** `GOOGLE_IOS_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` in `project.yml`
   are `REPLACE_ME` placeholders. Fill them from Google Cloud Console (iOS client, bundle id
   `app.cooked.paper`) and add the client id to the API's Google audiences. Until then the
   Google button says it isn't configured.
4. **Universal links.** The entitlement lists `applinks:cooked.trade` and
   `applinks:www.cooked.trade`; the web app must serve `/.well-known/apple-app-site-association`
   for your Team ID (`APPLE_TEAM_ID`, and `IOS_BUNDLE_ID` if it differs) on its Vercel project.
5. **App Store Connect.** Create the "Cooked Paper Pro" subscription group with the product
   IDs above, annual with a 1-week introductory free trial and monthly with none; annual.offer
   with no introductory offer; weekly removed from sale. Product IDs must match
   `ProductID`. Xcode may offer to repair the `.storekit` file's internal IDs; let it.
6. **API base URL.** `APIConfig.baseURL` reads `COOKED_API_BASE_URL` from Info.plist (filled
   from the build setting in `project.yml`); Debug and Release both default to
   `https://api.cooked.trade`. To use a local API change it under `configs: Debug:` and re-run
   `xcodegen generate`. Plain `http://` is allowed only for localhost and `.local` hosts. In
   an `.xcconfig` write `https:/$()/host`. A missing or malformed value falls back to production.

## Testing and CI

- Unit tests: `xcodebuild test -scheme CookedPaper` (Swift Testing). UI tests run against an
  in-process mock API, enabled only in DEBUG builds with `UITEST_MOCK_API=1`
  (`UITEST_MOCK_FRESH=1` starts signed out; `UITEST_BYPASS_PAYWALL=1` forces subscribed;
  `UITEST_STILL_FRAMES=1` stills animations). Mocks live in `Networking/Mock*.swift`.
- CI (`ios-build-and-screenshot.yml`, macOS 15, every push and manual dispatch): selects Xcode
  26, installs XcodeGen, generates the project, boots an iPhone 17 Pro simulator, runs the unit
  tests and the screenshot UI tests, then records the chart and trade UI tests as video, and
  uploads `ui-screenshots`, `live-chart-recording` and `xcresult-bundle` artifacts. It does not
  commit screenshots, publish to TestFlight or sign anything. Check the latest run before
  assuming a change compiles; there is no local Mac build in the authoring loop.

## Before shipping

- Owner-provided values: `DEVELOPMENT_TEAM`, the Google client ids, App ID capabilities, an APNs
  key on the backend, `APPLE_TEAM_ID` on the web app.
- Guest onboarding needs `PAPER_GUEST_SESSIONS_ENABLED=true` on the API (default false); without
  it the app signs in right after the practice round.
- A returning account owner who taps "Save your portfolio" gets the guest portfolio claimed, but
  the app keeps trading their oldest portfolio, so onboarding positions don't show there.
  "Already have an account? Sign in" avoids this.
- Numerals use the system monospaced design, not IBM Plex Mono as on web and Expo.
- Legal pages (`https://cooked.trade/legal/terms`, `/legal/privacy`) are linked from
  `LegalLinks.swift`. The sign-in screen states that continuing means acceptance and confirms
  18+. Before submitting, confirm the operator entity is active, `support@cooked.trade` is a live
  mailbox, the App Store privacy URL matches, the age rating is 17+ or higher, and
  `PrivacyInfo.xcprivacy` / App Privacy answers list push token and purchase history.

## App icon

`Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` is checked in. To regenerate it
after editing the design, on a Mac from `CookedPaper` run `swift Scripts/GenerateIcon.swift`.
