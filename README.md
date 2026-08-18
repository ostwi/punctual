# Punctual

A native macOS menu bar app for Google Calendar meetings — never walk in late again.

- **Menu bar countdown**: your next meeting and how long until it starts ("Standup in 12m")
- **Today at a glance**: click the menu bar item for today's remaining meetings with one-click **Join** (Google Meet, Zoom, Microsoft Teams)
- **Unmissable full-screen alert** when a meeting is about to start — Join / Snooze 1 min / Dismiss, shown over every app (even full-screen ones) on every display, with a configurable lead time (0/1/2/5 minutes)
- **Sign in with Google**, launch at login, 100% native SwiftUI

No Electron, no analytics, no servers: the app talks **directly** to the Google Calendar API from your Mac using two read-only scopes — `calendar.events.readonly` and `calendar.calendarlist.readonly`, the narrowest that cover reading your calendars and their events. Tokens live in your Keychain; calendar data never goes anywhere else.

Requires macOS 14.4+.

## Install

Until there's a notarized release build, build from source:

```
git clone <repo-url>
cd punctual
open Punctual.xcodeproj
```

Set Signing & Capabilities → Team to your (free) Personal Team, then Run. The app appears in the menu bar — there is no Dock icon.

If you received a pre-built `Punctual.app` instead: it isn't notarized, so on first launch approve it under **System Settings → Privacy & Security → "Open Anyway"**.

## Sign-in

The app ships with a shared OAuth client ID. Google has verified it for the sensitive Calendar scopes it requests, so sign-in is a normal Google consent screen — no "unverified app" warning, no user cap, and refresh tokens do not expire on a timer.

Punctual asks for two read-only scopes and nothing else: `calendar.calendarlist.readonly`, to see which calendars you have, and `calendar.events.readonly`, to read their events. It cannot create, edit, or delete anything.

## Architecture

```
PunctualApp (SwiftUI App)
 ├─ MenuBarExtra(.window)        menu bar label + dropdown
 ├─ Settings scene
 └─ AppState (@Observable)       single source of truth
      ├─ GoogleAuthController    OAuth 2.0 + PKCE via ASWebAuthenticationSession; tokens in Keychain
      ├─ CalendarService         Google Calendar REST v3 (today's + tomorrow's events, all selected calendars)
      ├─ RefreshCoordinator      60 s poll + wake-from-sleep refresh
      ├─ MenuTitleTicker         adaptive countdown timer (1 min / 1 s granularity)
      └─ AlertScheduler          wall-clock alarm + snooze/dismiss state machine
            └─ AlertWindowController  full-screen NSPanel per display, over full-screen apps
```

No third-party dependencies. Debug builds include **Settings → Debug → "Trigger test alert"** to preview the full-screen alert without waiting for a real meeting.

Unit tests live in `PunctualTests` (join-link extraction, the alert state machine, event dedupe, menu title formatting): `xcodebuild test -scheme Punctual -destination 'platform=macOS'`.

## Maintainer: OAuth client

The shared client ID in `Punctual/Auth/OAuthConfig.swift` is a public identifier — Google's "iOS" client type for installed apps has no client secret, and the code exchange is PKCE-protected, so committing it is safe and standard. Setup:

1. [console.cloud.google.com](https://console.cloud.google.com) → create a project → enable **Google Calendar API**.
2. **OAuth consent screen**: User type **External**. App name `Punctual`, your support email.
3. **Credentials → Create credentials → OAuth client ID** → type **iOS**, bundle ID `com.punctualapp.punctual`. Paste the resulting client ID into `OAuthConfig.swift`.
4. **Verification** — done for this client ID (approved August 2026). A fork with its own client ID needs to repeat it, since verification is per-project. It lifts the unverified-app warning and the 100-user cap:
   - Host a homepage and privacy policy on a domain you can verify in [Google Search Console](https://search.google.com/search-console) — a GitHub Pages site works.
   - On the consent screen, set the homepage, privacy policy URL, and authorized domain; add the `calendar.events.readonly` and `calendar.calendarlist.readonly` scopes with a justification ("displays the user's upcoming meetings in the macOS menu bar").
   - Publish to Production and submit for verification; sensitive-scope review typically takes a few days to a few weeks and may ask for a short demo video of the sign-in flow.

Forks that change the bundle ID must create their own client ID (it's bound to the bundle ID).

## License

[MIT](LICENSE)
