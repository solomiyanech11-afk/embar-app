# Embar

**A sidebar for Mac that removes the friction between having a thought and writing it down.**

Embar lives just beyond the right edge of your screen. Move the pointer there, or press ⌥E, and a
panel slides out over whatever you are doing, with the cursor already waiting in the input field.
Write the thought, move away, and you are back in your work. No window to find, no app to switch
to, no file to name.

<!-- SCREENSHOT: main panel -->
<!-- GIF: panel sliding in, a thought being captured -->

---

## What it does

Embar has three surfaces, each for a different kind of thinking.

### Stickies

For single thoughts, caught the moment they arrive. Sort them into walls, give one a deadline or a
reminder, pin what matters, mark things done. Drag a sticky past the edge of the panel and it
becomes a small note on your desktop, staying right where you can see it until you are finished
with it.

### Notes

For longer writing. Formatting, photos, quotes and lists. Type `[[` to link one note to another,
and every note shows where it is mentioned.

### Reader

A notebook for what you read, watch or listen to. Thoughts and quotes in one stream, highlights in
colour, threads to group entries by chapter, and a cover and a source link for each notebook. Embar
never opens the source itself. It keeps your thinking next to it.

### Made to stay out of the way

The panel hides when you leave and comes back when you need it. Lock it open when you want it to
stay. Make it yours with fifteen colour palettes. In English and Ukrainian.

### Your notes stay on your Mac

No account, no sign-in, no analytics. Everything you write is stored locally, in the app's own
container, and nothing is uploaded.

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
  Features/      Stickies · Reader · Notes · Settings · Onboarding · Paywall · Home (not shipped in v1)
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
git clone https://github.com/solomiyanech11-afk/embar-app.git
cd embar-app
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

Everything else - all three surfaces, the panel, the palettes - runs with no setup at all, because
the trial opens on first launch and nothing gates it.

---

## Project status

Embar is live product code, not a demo. Stickies, Notes, Reader, desktop stickies, onboarding,
settings, localisation and the paywall are done. iCloud sync and dark mode are in progress.

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
