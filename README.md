# Embar

**A sidebar for Mac that removes the friction between having a thought and writing it down.**

Embar lives at the edge of your screen. You nudge it with a hotkey or the pointer, it slides in, you
write, it slides away. Nothing to launch, no window to arrange, no file to name.

<!-- SCREENSHOT: main panel -->
<!-- GIF: panel sliding in, a thought being captured -->

---

## What it does

Embar is **one pipeline, not three tabs**. A quick thought, a line you underlined while reading, and a
fully-formed idea are not separate things - they are stages of the same flow, and the app models them
that way.

### Stickies - fleeting capture

Write a thought in one keystroke. Colour it from the active palette, give it a deadline with a
reminder, file it on a wall, pin it, let it auto-archive. Drag a sticky out of the panel and it
becomes a small always-on-top note on your desktop (up to ten at a time).

### Reader - an annotation layer over what you read

Not a book reader and not a read-later inbox. Embar never renders the source - it links to it and
keeps *your* thinking on top of it. Entries are typed as Thought, Quote, Question, Insight or Voice
memo. Text highlights in four fixed colours, `#tags` inline, favourites, search by text, author or
page, photo attachments, date dividers between days.

### Notes - where thoughts mature

Full notes with a title and a body, folders, pinning, photo attachments, and `[[title]]` links that
generate backlinks automatically: every note shows where it is mentioned.

### The connective tissue

This is the product, not a feature list:

- **Sticky → Note** (`matureSticky`) - a sticky grows into a real note, and the link is kept on both sides
- **Sticky → Todo** - the text lands on the day screen, the sticky stays where it is
- **Reader entry → Note** - append to an existing note or start a new one
- **Backlinks** - `[[mentions]]` resolved across the whole store

### Also in the box

A **Home** day screen (weekly ring strip, lane-packed timeline, todos, habit streaks) is fully built
but hidden behind a feature flag in v1. Fifteen named colour palettes that repaint the whole app,
Ukrainian and English localisation, a global hotkey (⌥E by default), and a lock mode that keeps the
panel open while you work.

---

## Built with

| | |
|---|---|
| **SwiftUI** | the entire UI |
| **AppKit** | the defining piece - an `NSPanel` that slides from the screen edge, auto-hides on focus loss, and hosts the desktop sticky windows |
| **SwiftData** | the single local store, CloudKit-compatible from day one |
| **StoreKit via RevenueCat** | the only third-party dependency ([`purchases-ios-spm`](https://github.com/RevenueCat/purchases-ios-spm), pinned) |
| **Carbon `RegisterEventHotKey`** | the global hotkey, which needs no Accessibility permission |

Roughly 43k lines of Swift, 47 test files. No package manager beyond SwiftPM, no build scripts, no
code generation.

---

## Architecture

```
Embar/
  Shell/         NSPanel controller, hotkey, desktop sticky windows, sandbox environment
  Features/      Stickies · Reader · Notes · Home · Settings · Onboarding · Paywall
  Models/        14 @Model types - one SwiftData store shared by every surface
  Theme/         palette + material system (colours, typography, motion tokens)
  Components/    shared controls, so the same affordance looks identical everywhere
  Monetization/  entitlement state, trial anchor
  Fonts/         Fraunces + Inter, with their SIL OFL licences
EmbarTests/      unit tests, including source-scanning guards
```

Three rules that shape most of the code:

- **CloudKit-ready schema from the first model.** Every property optional or defaulted, no
  `@Attribute(.unique)`, every relationship has an inverse, and nothing is hard-deleted - `deletedAt`
  marks a record and a purge removes it after 30 days.
- **Motion is earned.** Only real moving surfaces animate: the panel slide, sheets, toasts, toggles,
  and card reorder caused by a direct action on that card. Tab content, filters, counters and list
  re-sorts are instant.
- **Nothing visual comes from macOS settings.** Selection colour, caret, and accent are the app's own,
  applied through a memory-only defaults domain so the system's settings are never written to.

There is a second scheme, **Embar (Sandbox)**, that runs the app on a completely separate SwiftData
file and UserDefaults suite, so development and screenshots never touch real notes. A unit test scans
the sources to keep that isolation from rotting.

---

## Monetization

Free download, **14 full days with no card and no account** - the trial anchor is a date written to
the Keychain (data-protection, this-device-only, so it survives a container wipe) with a fallback in
the app's own defaults. After that, Embar drops to **read-only**: you keep everything, you can edit,
delete, archive, export and undo, but creating something new asks you to buy.

Purchases go through **StoreKit, brokered by RevenueCat** - a monthly subscription and a lifetime
unlock, with Restore Purchases, the standard Apple EULA and a privacy link in the paywall.

The policy under all of it is deliberately generous: *better to hand out access than to lock someone
out of their own notes*. If the trial has expired but RevenueCat has never answered - no network, a
firewall, a first run offline - the app stays open. Read-only turns on only when the cached answer
explicitly says "not subscribed".

---

## Privacy

- **Zero analytics.** No telemetry, no crash reporting, no tracking SDK, no first-run ping.
- **Your notes never leave your Mac.** SwiftData writes to the app's own container and nothing reads
  it but Embar.
- **The App Sandbox is on**, and every entitlement is a deliberate decision. There are three:
  outgoing network (RevenueCat only - there is no inbound access and no other network user),
  microphone (voice memos in Reader), and read-only access to files you pick yourself (photo
  attachments, which are copied into the container).
- **Permissions are asked for lazily**, at the moment you first use the feature that needs them.
- No secrets in the source. The only key in the repository is RevenueCat's *public* SDK key, which is
  designed to ship inside apps.

None of that is a promise you have to take on faith. The privacy manifest at
[`Embar/PrivacyInfo.xcprivacy`](Embar/PrivacyInfo.xcprivacy) declares no tracking, no tracking
domains and no collected data types, and the only required-reason APIs it lists are `UserDefaults`
for the app's own settings and system boot time for a click debounce.

---

## Building it

**Requirements:** macOS 14 (Sonoma) or later to run, Xcode 16 or later to build. Developed against
Xcode 26.2 with the Swift 5 language mode and `MainActor` default isolation.

```bash
git clone https://github.com/<you>/Embar.git
cd Embar
open Embar.xcodeproj
```

Then, before the first build:

1. **Set your own team.** Select the *Embar* target → *Signing & Capabilities* → *Team*. The
   committed project file still carries the original author's team ID, and signing will fail until
   you replace it. You may also want your own bundle identifier in place of `nechai.Embar`.
2. **Pick the `Embar` scheme** and ⌘R. Swift Package Manager will fetch RevenueCat on the first
   resolve; there is nothing else to install.

From the command line:

```bash
xcodebuild -project Embar.xcodeproj -scheme Embar -destination 'platform=macOS' build
xcodebuild -project Embar.xcodeproj -scheme Embar -destination 'platform=macOS' test
```

For day-to-day work without touching your real notes, use the **Embar (Sandbox)** scheme.

### About purchases in your own build

The paywall is wired to the original App Store Connect products and RevenueCat project, so a fork
will not be able to complete a real purchase. To exercise that path yourself you need your own
RevenueCat app and API key (`ProProducts.revenueCatAPIKey`), your own product identifiers, and a
StoreKit sandbox tester account - purchases in a development build are charged to nothing and appear
under the sandbox Apple Account, never a real one.

Everything else - all three surfaces, the links between them, the panel, the palettes - runs with no
setup at all, because the trial opens on first launch and nothing gates it.

---

## Project status

Embar is live product code, not a demo. Milestones 1 through 5 are shipped: the panel shell,
Stickies, Home, Notes and Reader, plus onboarding, settings, localisation, desktop sticky widgets and
the paywall. Current work is polish and the Milestone 6 backlog - iCloud sync, dark mode and Liquid
Glass, and the parked material-theme experiment.

The product and implementation specs, the test plan and the design research stay in a private
repository - they are written in Ukrainian and read as a working diary rather than documentation.
[`CLAUDE.md`](CLAUDE.md) is the one piece of that diary kept here: the standing rules this codebase
is written against, including a few hard-won ones (the isolated-`deinit` runtime landmine, the
defaults-isolation invariant that keeps the sandbox from writing into real settings).

---

## Licence

Embar is free software, licensed under the **GNU General Public License v3.0**. See
[LICENSE](LICENSE) for the full text.

You may use, study, change and share it. If you distribute a modified version, it must carry the same
licence and its source must be available.

### Bundled fonts

**Fraunces** and **Inter** ship in [`Embar/Fonts/`](Embar/Fonts/) under the **SIL Open Font License
1.1**. Their licence files sit beside them (`LICENSE-Fraunces-OFL.txt`, `LICENSE-Inter.txt`) and
travel with the fonts, not with this project's licence.

### Trademarks

**The GPL covers the code. It does not cover the brand.**

The name **Embar**, the Embar logo, the Embar mark and the application icon are **not** licensed
under the GPL. All rights reserved. © 2026 Solomiia Nechai.

If you fork this project and distribute your version, please give it your own name and your own icon.
You are welcome to say that it is derived from Embar - please do not present it as Embar.
