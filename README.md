# WatchList

[![CI](https://github.com/Mohsin-Bhojani/WatchList/actions/workflows/ci.yml/badge.svg)](https://github.com/Mohsin-Bhojani/WatchList/actions/workflows/ci.yml)

An iOS app for keeping track of the films and TV you mean to watch, are part-way
through, and have finished — built with SwiftUI and SwiftData, with everything
about a title pulled from [The Movie Database](https://www.themoviedb.org).

## Features

- **Library** — shows and films side by side, sorted by date added, title, year,
  status or rating, with per-status tallies at the top.
- **Import from a link or a search** — paste an IMDb URL or search TMDb, and the
  poster, synopsis, genres, technical specs and (for a show) every season and
  episode arrive with it. Titles already in your library are flagged in the
  search results so you don't add them twice.
- **Shows → Seasons → Episodes** — each level has its own page, its own watch
  status and its own rating. Marking a show watched can cascade to everything
  under it.
- **Cast, Similar and Images tabs** on every Show, Season, Episode and Film page.
  Similar rows are addable to the library in one tap. A tab that TMDb has nothing
  for removes itself rather than sitting there empty.
- **Ratings** — Perfection, Go For It, Timepass, Skip for shows and films;
  Rewatch / Watch / Skip per episode.
- **Stats** — status and rating breakdowns across the whole library, each row
  tappable to see the titles behind it.
- **New episodes** — shows are topped up with newly aired seasons and episodes at
  most once a day. Additive only: your watch marks, ratings and notes are never
  touched.
- **Artwork** — every show, season, episode and film opens TMDb's gallery from
  its menu, and any image there can be made the title's poster (portrait) or its
  landscape artwork. What's chosen is what the app draws it from everywhere,
  Home's hero and the watch included.
- **Everyone on WatchList** — how everyone who rated a title rated it: the
  rating most gave as a headline, the spread beneath it, and where yours sits.
  The ratings come through one seam (`CommunitySource`); the only source today
  is the device itself, so the count is your own rating and nothing is sent
  anywhere. A server can go behind the same seam later.
- **Six accent palettes**, changeable in-app or from the iOS Settings app.
- **Apple Watch** — a companion app that also runs on its own. *Up Next* pages
  sideways through the shows set to Watching; Mark Watched opens Skip / Watch /
  Rewatch, and picking one marks the episode, with Undo. *Discover*, a Crown turn
  below, deals suggestions one poster at a time, fetched from TMDb on the watch:
  tap for the synopsis, swipe right to add, left if not interested, up for later,
  with Filter top left. The watch keeps the last sync, so it works away from the
  iPhone. See [Apple Watch](#apple-watch).

## Requirements

| | |
|---|---|
| Xcode | 26.2 or later (needs the iOS 26.2 SDK) |
| iOS | 26.2 or later |
| watchOS | 26.0 or later, for the watch app |
| Swift | 5.0 language mode |

No package dependencies — the project builds straight from a checkout.

## Getting started

### 1. Get a TMDb API key

TMDb accounts are free. Sign up, then copy your **API Key (v3 auth)** from
<https://www.themoviedb.org/settings/api>.

### 2. Put the key where the build can find it

```bash
cp Configuration/Secrets.example.xcconfig Configuration/Secrets.xcconfig
```

Open `Configuration/Secrets.xcconfig` and fill in the key:

```
TMDB_API_KEY = your_key_here
```

`Secrets.xcconfig` is listed in `.gitignore` and is never committed. The build
carries the value into the app's generated `Info.plist`, and `TMDbConfig` reads
it back at runtime — the key is not in any tracked source file.

Without the file the project still compiles; the app simply reports that no key
is configured wherever it would have fetched something.

Optionally, add a Trakt client id on the next line, for **Open in… Trakt**.
Create a free API app at <https://trakt.tv/oauth/applications/new> (any name,
redirect URI `urn:ietf:wg:oauth:2.0:oob`) and paste its Client ID:

```
TRAKT_CLIENT_ID = your_client_id_here
```

Without it, Trakt is simply left out of the menu.

### 3. Build and run

```bash
open WatchList.xcodeproj
```

Pick your own team under **Signing & Capabilities** (the project ships with no
team set), choose an iOS 26 simulator, and run.

> **One thing to watch:** once you set a team, Xcode writes it back into
> `project.pbxproj` as `DEVELOPMENT_TEAM = ABCDE12345`. That is your own
> identifier and does not belong in a shared commit, so drop it before you push:
>
> ```bash
> git checkout -- WatchList.xcodeproj/project.pbxproj
> ```
>
> Simulator builds and CI need no team at all.

## Apple Watch

The watch app (`WatchList Watch App`, bundle ID `com.mohsin.WatchList.watchkitapp`)
is embedded in the iPhone app and marked as able to run without it. No
capabilities or entitlements are needed — no App Groups, iCloud or push — so a
free Personal Team can sign it.

- **The library stays on the iPhone.** `WatchList/WatchSync.swift` sends the watch
  a snapshot — Up Next, the titles Discover starts from, and what it leaves out —
  as the WatchConnectivity *application context* whenever the library changes.
- **The watch's actions** (a mark, a rating, Undo, Add / Not interested / Later)
  are queued with *transferUserInfo*, and also sent as a *message* while the
  iPhone is reachable so they show at once. The iPhone applies each one once,
  through the same code its own screens use, and names it in the next snapshot.
  Until then the watch lays its actions over the last snapshot
  (`WatchOutbox`), so it never waits for the iPhone.
- **A refresh message** asks the iPhone for a snapshot straight away when the
  watch app opens or the iPhone comes back in reach.
- **Discover on the watch** fetches from TMDb itself, using the same queue,
  filter and rotation as the iPhone (`Shared/DiscoverQueue.swift`). The watch
  build reads the key from the same `Secrets.xcconfig`.
- **Offline**, the watch shows the last snapshot (kept in Application Support)
  and cached artwork, and holds its actions until the iPhone is back.

### Trying it in the simulators

Pair a watch simulator with an iPhone simulator, install the **iPhone app first,
then the watch app** — the other way round, the iPhone's session reports the
watch app as not installed. A Debug build of the watch app with `-WatchListSample`
in the scheme's Run arguments runs on a made-up library without an iPhone
(`simctl launch` doesn't pass arguments on to a watch app).

Simulators deliver the application context and messages, but not queued
`transferUserInfo`: a watch action taken while the iPhone is unreachable only
reaches it on a real device.

## Running the tests

```bash
xcodebuild test -project WatchList.xcodeproj -scheme WatchList -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The unit tests are pure logic — decoding TMDb payloads and the mapping either
side of the network calls — so they pass without an API key. That is also why
CI (`.github/workflows/ci.yml`) needs no secret configured: it checks out,
picks whichever iPhone simulator the runner has, and runs the same command.

## Project layout

```
WatchList/
├── WatchListApp.swift        App entry point and SwiftData container
├── Models.swift              Show / Season / Episode / Film, statuses, ratings
├── WatchSync.swift           The iPhone's end of the watch link
├── ImportCoordinator.swift   A link or a search pick → populated models
├── CreditsLoader.swift       Cast / Similar / Images mapping and session cache
├── LibraryRefresher.swift    The once-a-day new-episode top-up
├── DesignSystem.swift        Colours, typography, materials
├── Components.swift          Shared rows, cards, pickers, tab bar
└── *View.swift               Screens
Shared/                       Compiled into both apps: library values, the TMDb
                              client, Discover's queue, the watch link, app icon
WatchList Watch App/          The watch app: PhoneSync, WatchStore, Up Next, Discover
Configuration/                xcconfig files (the API key lives here, untracked)
WatchListTests/               Swift Testing unit tests
WatchListUITests/             XCUITest launch tests
```

## Attribution

This product uses the TMDb API but is not endorsed or certified by TMDb.

## Licence

[MIT](LICENSE).
