# Nuvora

**Personal real-time news, podcast and live-audio hub for Windows.**

Nuvora is a local-first Windows desktop application that turns RSS/Atom and open podcast feeds into a programmable information stream: follow a topic, choose cadence, receive native notifications, and listen without living in a browser.

## Runnable vertical slice

- Native Windows desktop UI (WPF/.NET 9)
- RSS + Atom ingestion
- Podcast enclosure discovery and playback
- Podcasting 2.0 namespace-aware parser foundation, including `liveItem`
- Native actionable Windows notifications
- SQLite persistence and deterministic SHA-256 deduplication
- Per-topic polling/delivery domain model
- HTTP timeout + standard resilience pipeline
- Local data under `%LOCALAPPDATA%/Nuvora`
- Core separated from Windows host

## Integration map

Nuvora does not blindly vendor third-party code. Integrations live behind adapters/protocol boundaries so upstream projects can evolve independently and licenses remain auditable.

1. Windows App SDK / Windows notifications — native notifications and future MSIX lifecycle.
2. Podcast Index — primary open podcast discovery/search target.
3. Podcasting 2.0 — live items, transcripts, chapters, people and modern metadata.
4. FreshRSS — optional Google Reader-compatible source; WebSub patterns.
5. gPodder / goPodder — subscription and playback-position sync.
6. AntennaPod — interoperability target via open standards; no copied Android code.
7. ntfy — optional remote notification bridge.
8. changedetection.io — optional web-change source for pages without feeds.
9. ArchiveBox — optional save-for-later archival handoff.
10. Linkwarden — optional bookmark/archive destination.
11. OPML — portable import/export.
12. WebSub — push-first feed updates where supported.

## Build

Requirements: Windows 10/11, .NET 9 SDK, VS Code or Visual Studio.

```powershell
git clone https://github.com/MukaSanches/Nuvora.git
cd Nuvora
dotnet restore
dotnet build -c Debug
dotnet run --project src/Nuvora.App/Nuvora.App.csproj
```

Paste an RSS/Atom/podcast feed URL. Nuvora fetches it, stores unseen items, emits notifications for immediate topics, and lists content. Double-click a podcast to play it; double-click news to open the original source.

## Architecture

```text
Sources -> Provider adapters -> FeedEngine -> SQLite
                                   |       -> Timeline/UI
                                   +----------> Notification sinks
                                   +----------> Audio player

Podcast Index / RSS / WebSub / web-change
              | common ContentItem contract
              v
      scheduling + dedupe + policy
```

## Engineering principles

Local-first; cancellation-aware async I/O; deterministic dedupe; bounded network timeouts; provider isolation; no secrets in source; explicit third-party boundaries; original-source links preserved; graceful degradation; no hidden surveillance behavior.

## Next production gates

Persistent subscription editor and scheduler worker; Podcast Index credentials via Windows Credential Manager; MSIX identity/notification activation; background startup option; full Podcasting 2.0 live-state handling; OPML; gPodder sync; transcript/chapter UI; download manager; media-session integration; accessibility/localization; fixture-based integration tests; signed packages and CI release artifacts.

## Status

This is beyond a static mockup: the repository contains an end-to-end ingestion/storage/notification/playback path. It is not claimed release-perfect until CI and Windows hardware validation pass.
