# Cooked Paper (iOS)

A native SwiftUI, paper-trading-only companion to Cooked, hard-paywalled at **$7.99/mo**
or **$29.99/yr**. Built against the same `apps/api` backend as `apps/web` and
`apps/mobile`. The subscription is enforced on-device via StoreKit 2, with the
server consulted as a second opinion once its Apple billing routes are deployed
(see "Subscriptions" below).

It was scaffolded on a machine with no Xcode, but it is now built on every push by
GitHub Actions on a macOS runner (`.github/workflows/ios-build-and-screenshot.yml`):
`xcodegen generate`, a full simulator build, the unit tests, and the UI screenshot
walkthrough against the in-app mock API. Check that workflow's latest run before
assuming a change compiles. Read this whole file before opening the project — a few
values are owner-provided and must be filled in before it will sign or run against
real services.

**Requires Xcode 26+ to build**, even though the app's own deployment target stays
iOS 17 — the UI adopts Liquid Glass (`glassEffect`, `.glassProminent`,
`GlassEffectContainer`, all iOS 26+ only) as a progressive enhancement, and every use
is gated behind `if #available(iOS 26.0, *)` with a pre-26 fallback. That gating still
needs the iOS 26 SDK to be *present* to compile at all — an older Xcode without that
SDK will fail on the `Glass`/`glassEffect` symbols regardless of the availability
check, since the check only decides which code *runs*, not which code *compiles
against a known symbol*. Today the only glass surface is the floating tab bar
(`TabBarBackground` in `Sources/App/AppShellView.swift`).

## What's here

```
CookedPaper/
  project.yml              XcodeGen spec — the source of truth. The .xcodeproj is
                            generated from this and gitignored.
  Sources/
    App/                    Entry point, paywall/onboarding gate, deep-link routing,
                            the shared portfolio store
    DesignSystem/           Colors/type/motion ported from packages/config/design-tokens.ts,
                            plus skeleton-loading components
    Networking/             APIClient, Keychain session storage, the /paper and
                            /market Socket.IO clients (with the real
                            resume/gap/heartbeat protocol), alerts/push/billing APIs,
                            and the DEBUG-only MockAPI the UI tests run against
    Models/                 Codable models, incl. the DecimalString wrappers every
                            money field on this API needs (see Models/DecimalCodable.swift)
    Paywall/                StoreKit 2 subscription store + the paywall screen
    Features/               Onboarding, Discover, TokenDetail
                            (chart + trade), Trade, Leverage, Alerts, Portfolio,
                            Leaderboard, Compete (seasons, achievements, duels),
                            Profile, Settings
  Resources/                Info.plist, entitlements, Assets.xcassets
  Scripts/                  GenerateIcon.swift — renders the real app icon PNG
  StoreKit/Products.storekit  Local StoreKit Configuration for the two subscriptions
  Tests/                    Swift Testing unit tests (decimal codec, Base58, trade
                            math, model decoding)
```

## First-time setup

1. **Install XcodeGen** (`brew install xcodegen`), then from `CookedPaper` (this
   repo's own `apps/ios/CookedPaper` if you're reading this inside the monorepo it
   was extracted from):
   ```
   xcodegen generate
   open CookedPaper.xcodeproj
   ```
2. **Apple Developer / signing** (owner-provided)
   - `DEVELOPMENT_TEAM` in `project.yml`'s `settings.base` is deliberately empty in the
     repo: set it to your Team ID (or set it in Xcode's Signing & Capabilities tab).
     CI doesn't need it — it builds with `CODE_SIGNING_ALLOWED=NO`.
   - Bundle id is `app.cooked.paper`, matching the `app.cooked.mobile` convention the
     Expo app already uses. Enable **Sign in with Apple**, **Push Notifications**
     and **Associated Domains** on the App ID. The `aps-environment` entitlement
     comes from the `APS_ENVIRONMENT` build setting: `development` for Debug,
     `production` for Release.
   - Universal links (`https://cooked.trade/d/<code>`, `/l/<code>` opening the app)
     use the `applinks:cooked.trade` / `applinks:www.cooked.trade` entitlement in
     `project.yml`. iOS only honours them once the web app serves
     `/.well-known/apple-app-site-association` for this Team ID: set
     `APPLE_TEAM_ID` (and `IOS_BUNDLE_ID` if it ever differs from
     `app.cooked.paper`) on the web's Vercel project.
3. **App Store Connect — subscriptions**
   - Create a subscription group ("Cooked Paper Pro") with two auto-renewable
     subscriptions: `app.cooked.paper.monthly` ($7.99/mo) and
     `app.cooked.paper.annual` ($29.99/yr). These product IDs must match
     `Sources/Paywall/SubscriptionStore.swift`'s `ProductID` exactly.
   - `StoreKit/Products.storekit` mirrors this for local testing (Xcode scheme →
     Options → StoreKit Configuration) without needing App Store Connect at all
     during development. Xcode will offer to repair its internal IDs the first time
     you open it — let it.
4. **API base URL** — `APIConfig.baseURL` (`Sources/Networking/APIClient.swift`) reads
   the `COOKED_API_BASE_URL` Info.plist key, which `project.yml` fills from the build
   setting of the same name under the target's `settings.configs`. Debug and Release
   both default to `https://api.cooked.trade` (the backend behind Cloudflare; see
   `docs/deploy-oracle.md` in the backend repo). REST and both sockets use it.
   - To point **Debug** at a local or staging API, change `COOKED_API_BASE_URL` under
     `configs: Debug:` in `project.yml` (e.g. `http://localhost:3000` for an API on
     the Mac running the simulator, or `https://staging.example.com`) and re-run
     `xcodegen generate`. Plain `http://` is allowed only for localhost and `.local`
     hosts (`NSAllowsLocalNetworking`); a physical phone needs your Mac's
     `.local` name or an https tunnel. If you override it from an `.xcconfig`
     instead, write `https:/$()/host` — `//` starts a comment there.
   - A missing, empty or malformed value falls back to production, never to nothing.

## Product decisions this was built against

- **Everyone signs in: Apple or Google.** No guest sessions. Sign-in
  happens in onboarding right after the practice round; each provider proves
  identity to `apps/api`, which mints the session (access token + a refresh token
  returned in the body because the app sends `X-Cooked-Client: ios`, stored in the
  Keychain). The portfolio belongs to the account, so it follows the person to any
  device. Settings has Sign out and Delete account (App Store 5.1.1(v)). There is
  no wallet login (Privy was removed; there is no real trading).
  - **Google** needs the iOS OAuth client id (owner-provided): `GOOGLE_IOS_CLIENT_ID`
    and `GOOGLE_REVERSED_CLIENT_ID` in `project.yml` are `REPLACE_ME` placeholders in
    the repo. Fill them in from Google Cloud Console → Credentials → iOS client
    (bundle id `app.cooked.paper`) and add that client id to the API's Google
    audiences. Until then the Google button says it isn't configured.
  - **Apple** needs the Sign in with Apple capability on the App ID
    (`app.cooked.paper`); the entitlement is already in `project.yml`.
- **No dark patterns**, on purpose, matching `apps/api/src/paper/onboarding.ts`'s own
  stated design: no streaks, no countdowns, no fake urgency, no score. The backend
  structurally can't produce that data; the client doesn't invent it either.
- **Money is `Decimal`, never `Double`**, decoded from the API's decimal-STRING
  fields via `@DecimalString`/`@OptionalDecimalString` property wrappers. Every
  numeric UI value should trace back to one of these — never hand-parse a price
  string with `Double(string:)`.
- **Null means "unmeasured," never zero** — `PnLText` and the position/round-trip
  rows render `nil` as "—", matching the API's own convention. Don't "fix" a `nil`
  by coalescing it to `0`.
- **The live socket implements the server's real resume protocol**, not a
  simplification — it tracks the last seen `seq` per portfolio, resumes with
  `sinceSeq` on reconnect, and treats a `counterReset`/`truncated` gap as a fresh
  baseline rather than trying to replay deltas. A heartbeat watchdog tears down and
  reconnects the socket if `heartbeatIntervalMs` elapses with no tick.
- **`cookedpaper://token/<mint>` opens a token's detail screen** from anywhere in the
  app via `DeepLinkRouter`, presented as a sheet over whichever tab is active.
- **The chart's crosshair requires a brief press before it engages** (`LongPressGesture`
  sequenced before the drag, in `CandleChartView.crosshairGesture`), not a bare drag.
  The chart lives inside a `ScrollView`; a bare `DragGesture` there would capture every
  page-scroll attempt that happens to start over the chart. A quick swipe scrolls the
  page; a deliberate press-and-hold-then-drag scrubs the chart.

## Push notifications and price alerts

- **Permission is asked at a moment of intent** — creating a price alert, or after a
  trade — never at launch. Once allowed, the app registers with APNs on every launch
  and sends the hex device token to `POST /social/apns-tokens`
  (`{ deviceToken, environment }`, `sandbox` for Debug builds, `production` for
  Release) after registration, on launch and after every sign-in. Sign-out revokes
  it first with `POST /social/apns-tokens/revoke`.
- A push whose payload has a top-level `"mint"` opens that token (the same
  `cookedpaper://token/<mint>` path as a deep link); banners also show while the app
  is open.
- **Price alerts** use the existing `GET/POST/PATCH/DELETE /social/alerts` routes
  with `price_crossed` rules (channel `push`, 5-minute cooldown): the bell on a
  token's screen sets one (price prefilled, ±10/25% chips, above/below inferred from
  the target), active levels are drawn on the candle chart, and Settings → Price
  alerts lists, pauses and deletes them.
- **Status:** the alert and `/social/apns-tokens` routes exist in the backend; the
  server refuses token registration (`bad_request`) until an APNs key is configured
  on the deployment, which the app treats as a silent no-op. Guests' tokens are held
  and registered after sign-in.

## Compete: seasons, achievements, duels

The fourth tab is **Compete** (it replaced Leaderboard, which lives on inside it):
a segmented Season · Duels · Leagues · Leaderboard screen. Everything is paper money with no
stakes, and the season and duel screens say "No stakes. Paper money only. Results
are simulated."

- **Seasons** (`GET /paper/seasons/current`, `/history`, `/:id/results`): this
  month's tier, rank, return, a live countdown and how far to the next tier (or
  what it takes to qualify), the tier ladder, the top 10, and past seasons.
- **Achievements** (`GET /paper/achievements`, `POST /paper/achievements/seen`):
  a grid in Profile and on the Season page. Unlocks are decided by the server and
  celebrated with a toast — live from `paper:achievement` on the `/paper` socket,
  and on every return to the foreground for anything still `seen: false`.
- **Duels** (`/paper/duels…`): head-to-head with a fresh $1,000 paper portfolio
  each, by username or an open invite link (`https://cooked.trade/d/<code>`,
  `cookedpaper://duel/<code>`), for 1h, 24h or 7d. A duel's Trade button opens the
  normal buy/sell/leverage tickets with `TradePortfolioContext.duel`, so duel
  trades only ever touch that duel's portfolio. Detail refreshes every ~5 s and on
  `paper:duel` socket events.
- **Friend leagues** (`/paper/leagues…`): private leaderboards joined by invite
  code (`https://cooked.trade/l/<code>`, `cookedpaper://league/<code>`), ranked on
  the same season return. Create, join with a code, standings (ranked, then not yet
  qualified), invite sharing; the owner can rename, rotate the code, remove members
  and delete; members can leave.
- Deep links and pushes: `https://cooked.trade/d/<code>` and `/l/<code>` open the
  duel / league invite as universal links (same as `cookedpaper://duel/<code>` and
  `cookedpaper://league/<code>`); `cookedpaper://duel-id/<id>` or a push with
  `duelId` opens a duel; `leagueId` opens a league; a push with `achievementId` opens the
  achievements grid.
- **Status:** the backend routes are being built to the shared compete spec. Until
  they're deployed, a 404 hides the feature behind a calm "coming soon" state; the
  DEBUG mock (`MockCompete`) serves all of it for the UI tests and screenshots.

## Subscriptions

StoreKit 2 decides on the device as before. In addition, every verified
transaction's signed JWS is sent to `POST /billing/apple/transactions`
(`{ signedTransaction }`) — after a purchase or renewal, on restore, and for current
entitlements on launch and after sign-in — and `GET /billing/apple/entitlement` is
read back. Purchases carry `appAccountToken` = the account id when it's a UUID (a
guest buying before sign-in has none; the transaction is sent once they sign in).
The person is subscribed if StoreKit says so **or** the server says active; an
unreachable server, a 404 or an inactive answer never takes away a StoreKit
entitlement.

The annual plan has a 7-day free trial (weekly keeps its 3-day one). When the Apple
ID is eligible, the paywall says "Start 7-day free trial", shows a three-step "how
your trial works" timeline, offers a soft "want a reminder?" ask before the purchase,
and schedules a local reminder two days before the trial converts.

## Known gaps / what to do before shipping

- **Guest onboarding needs `PAPER_GUEST_SESSIONS_ENABLED=true` on the API.** It
  defaults to `false` (and production's example env says `false`); with guests off
  the app falls back to signing in right after the practice round, as before.
- **A returning account owner who taps "Save your portfolio"** gets the guest
  portfolio claimed into their account, but the app keeps trading their oldest
  portfolio, so the onboarding positions don't show there. "Already have an
  account? Sign in" on the first screen avoids this.
- **Owner-provided values:** `DEVELOPMENT_TEAM`, `GOOGLE_IOS_CLIENT_ID` /
  `GOOGLE_REVERSED_CLIENT_ID` (see First-time setup), plus the App ID capabilities
  (Sign in with Apple, Push Notifications, Associated Domains), an APNs key on the
  backend, and `APPLE_TEAM_ID` on the web app for universal links.
- **Numerals use SF Mono, not IBM Plex Mono.** The web/Expo apps both set prices in
  IBM Plex Mono; this port uses the system monospaced design (`.monospacedDigit()` in
  `Sources/DesignSystem/DesignSystem.swift`) instead of bundling the font files. Swap
  in the real TTFs under a new `Resources/Fonts` if exact brand parity matters more
  than the dependency.
- **Legal documents.** The app links to `https://cooked.trade/legal/terms` and
  `/legal/privacy` (`Sources/App/LegalLinks.swift`), which are in force (v1.0, paper-only,
  operator ZEVRON LLC). The sign-in screen states that continuing with Apple or Google is
  acceptance and confirms the user is 18+. Before submitting: the LLC must show as active
  on Sunbiz, `support@cooked.trade` must be a live mailbox, App Store Connect's privacy
  policy URL must be the one above, the App Store age rating must be 17+ (or higher) to
  match the 18+ term, and `Resources/PrivacyInfo.xcprivacy` / the App Privacy answers
  should list push token and purchase history, which the Privacy Policy discloses.
- **App Store Server Notifications** go to `POST /billing/apple/notifications`;
  set that URL in App Store Connect so the server learns about renewals and refunds
  without the device.
- **CI is the only compiler in the loop.** The project is generated and built on a
  macOS runner on every push; there's no local Mac build in the authoring loop, so a
  red CI run is the first place to look after any change.

## What was deliberately left out of v1

No social/community feed, no multiple-portfolio management UI (the app always trades
the caller's one "starter" portfolio), no watchlist. Leaderboard, onboarding, deep
linking, leverage and price alerts all shipped despite the original "don't need a ton
of features" framing — each was cheap given how much the backend already provides,
and none of them touch the paper-trading-only, no-real-money scope.

## First run

Balance → practice round → two questions (experience, goal) → pick three coins →
live portfolio → "Save your portfolio" sign-in → paywall → the app. Sign-in comes
after the guest has traded but before the purchase, so every subscription belongs to
an account. Everything before sign-in runs as a **guest paper session** (`POST /paper/portfolios/starter`
with no `Authorization` mints a 7-day guest token, kept in the Keychain); signing in
claims it (`POST /paper/portfolios/claim`) so the positions carry over. The first
screen has "Already have an account? Sign in". After
the first fill, a soft card asks whether to send price notifications (the system
prompt only follows a yes). The paywall headline follows the goal answer and shows
this month's top trader from the public leaderboard when there's a positive one.

A profitable sell or leveraged close asks for an App Store review (at most once per
90 days, never after a loss). Sells and closes offer a share button for the
server-rendered P&L card (`/cards/meta/…`, percentages only), hidden when the card
endpoint doesn't answer.

Share cards are also drawn on device (`DesignSystem/ShareCardRenderer.swift`):
`ImageRenderer` turns a 360×450pt SwiftUI card into a 1080×1350 PNG that `ShareLink`
shares with a line ending in cooked.trade. No endpoint: only the token logo is
fetched. Trade card (Token Detail's "Your position", and a sell's confirmation in
place of the link card), duel result card (a finished duel), and Daily Call streak
card (the icon in the Daily Call header).

## Live data

- Token charts: LIVE streams trade by trade from the `/market` socket (1 s REST
  polling as a fallback). Other ranges refetch their candles in place while on screen
  (1H every 15 s, 1D every 30 s, 1W every 60 s, 1M/ALL every 120 s), fold the live
  price into the current candle, and the header price is live on every range.
- Discover refreshes every 30 s and Leaderboard every 60 s while visible, silently,
  and on returning to the foreground.
- Both sockets re-read the access token before every reconnect and, if a handshake
  is refused, refresh the session the same way a REST 401 does.
- A small banner appears app-wide while the device is offline.

## Generating the app icon

`Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` is checked in. To
regenerate it after changing the design, on a Mac, from `CookedPaper`, run:

```
swift Scripts/GenerateIcon.swift
```

This renders `Scripts/GenerateIcon.swift`'s SwiftUI view (a candlestick pair in the
app's brand colors) via `ImageRenderer` and writes a real, opaque, alpha-free
1024×1024 PNG straight to
`Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. Re-run it any time to
regenerate the icon after changing the design in that script.
