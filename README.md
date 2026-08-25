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
- **Six accent palettes**, changeable in-app or from the iOS Settings app.

## Requirements

| | |
|---|---|
| Xcode | 26.2 or later (needs the iOS 26.2 SDK) |
| iOS | 26.2 or later |
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

### 3. Build and run

```bash
open WatchList.xcodeproj
```

Pick your own team under **Signing & Capabilities** (the project ships with no
team set), choose an iOS 26 simulator, and run.

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
├── TMDbService.swift         Every TMDb request, and TMDbConfig (the key)
├── ImportCoordinator.swift   A link or a search pick → populated models
├── CreditsLoader.swift       Cast / Similar / Images mapping and session cache
├── LibraryRefresher.swift    The once-a-day new-episode top-up
├── DesignSystem.swift        Colours, typography, materials
├── Components.swift          Shared rows, cards, pickers, tab bar
└── *View.swift               Screens
Configuration/                xcconfig files (the API key lives here, untracked)
WatchListTests/               Swift Testing unit tests
WatchListUITests/             XCUITest launch tests
```

## Attribution

This product uses the TMDb API but is not endorsed or certified by TMDb.

## Licence

[MIT](LICENSE).
