# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Note for the public repository.** This file is kept as-is, the way it is used in day-to-day
> development. It refers throughout to a `docs/` folder - the product spec, the implementation spec,
> the test plan and the design research - which lives in a private repository and is not published.
> The rules below still describe how this codebase is written; only the cross-references are dangling.

## Робота над проєктом (читати першим)

Це **macOS sidebar-застосунок Embar**.

- **Джерело істини** — `docs/Embar.md` (продукт, дизайн-система, технічні вимоги, roadmap) і `docs/quicknote-prototype-home.html` (точний вигляд і поведінка). При будь-якому питанні дивись туди, **не вигадуй**.
- Строго дотримуйся розділу **«Безпека, Sandbox і дозволи»** з `docs/Embar.md` (§12).
- Автор **новачок у Swift** — пояснюй рішення простими словами, без жаргону.
- Працюємо **по одному milestone за раз**. Після кожного автор сам збирає проєкт у Xcode і перевіряє — не переходь до наступного, поки поточний не підтверджено.
- Роби **`git commit` після кожного завершеного кроку**.
- Роби **`git push` після закриття кожного milestone** (коли користувач підтвердив). Remote: приватний `github.com/solomiyanech11-afk/Embar`; `gh` лежить у `~/.local/bin/gh`.

## Project state

Embar is **live product code**: Milestones 1–5 are shipped (Foundation, Stickies, Home, Notes, Reader — see `docs/Embar.md` §14 for what each contains). The panel shell (`Embar/Shell/`), the four surfaces (`Embar/Features/`), the palette + material theme system (`Embar/Theme/`), and a test target (`EmbarTests/`) all exist. Current phase: polish + the M6 backlog; the Glass/Levitation material theme is partially built (steps 1–7, parked — see `docs/BACKLOG.md`).

`docs/` is the source of truth for what to build:
- **`docs/SPEC.md`** — the formal implementation spec: every screen, all states, the exact SwiftData model (CloudKit-ready), cross-surface links, resolved discrepancies, and decisions log (§15). Read this first for implementation work.
- **`docs/Embar.md`** — the master product/design spec (in Ukrainian). It defines the surfaces, design system, milestones, and technical/security requirements. When a design decision is made, it belongs here (and in SPEC.md).
- **`docs/Brand-Foundation.md`** — brand, positioning, voice & tone (English).
- **`docs/quicknote-prototype-home.html`** — the working HTML/CSS/JS prototype (~14k lines). **The single visual source of truth**, but only the elements that are **actually visible and active** when opened in a browser. ⚠️ It contains dead/hidden legacy (elements with `display:none`, no-op functions, superseded styles). Before implementing any element, verify its real `display` state — do not trust mere presence in the code. Known legacy is catalogued in SPEC.md §14 (e.g. the `.new-btn` FAB is `display:none`; the walls bar `.reader-folder-bar` is a transparent float, not a solid docked row).
- 🚫 **`docs/quicknote-design-system.html` — DEPRECATED. Do not use as a source** (stale iteration: 1 palette, system fonts). Kept only as history.

Decision (2026-07-02): minimum is **macOS 14 (Sonoma)** — the deployment target is 14.0 (done in M1). Liquid Glass only behind `#available(macOS 26, *)`. Visual source of truth is the **prototype** (not the old §9.3–9.5 "phone frame" values); panel sizing spec is in SPEC.md §1.1.

## Build & run

Standard Xcode project — no package manager or external dependencies.

```bash
# Build (macOS)
xcodebuild -project Embar.xcodeproj -scheme Embar -destination 'platform=macOS' build

# Build & run tests (target: EmbarTests)
xcodebuild -project Embar.xcodeproj -scheme Embar -destination 'platform=macOS' test

# Run a single test
xcodebuild test -project Embar.xcodeproj -scheme Embar -destination 'platform=macOS' \
  -only-testing:EmbarTests/SomeTestClass/testSomething
```

For day-to-day work, open `Embar.xcodeproj` in Xcode and use ⌘R / ⌘U. The `/run` skill can launch the app to verify a change.

### Test sandbox (scheme «Embar (Sandbox)»)

Runs the app on **completely separate data** — a separate SwiftData file
(`Application Support/EmbarTestSandbox/sandbox.store`) and a separate
UserDefaults suite (`nechai.Embar.TestSandbox`). Real user data is never
read or written. Verified by `EmbarTests/SandboxIsolationTests` plus a
manual before/after checksum of the real container (2026-08-07).

The scheme carries three more arguments, disabled — tick them in the
scheme editor: `-SandboxResetOnboarding`, `-SandboxSeedStress 5000`,
`-SandboxWipe`. The same commands live in the «Пісочниця» window that
only exists in this mode.

`-SandboxShot YES` dumps every visible window to a PNG in the container's
Documents (rendered in-process, so it needs no Screen Recording
permission). Note: materials/blur are composited by the window server and
do **not** appear in these shots — glass reads as a flat slab there.

**Invariant:** app code contains **no `UserDefaults.standard`** — it uses
`EmbarDefaults.store` (see `Embar/Shell/SandboxEnvironment.swift`), and
every SwiftUI hosting root sets `.defaultAppStorage(EmbarDefaults.store)`
so `@AppStorage` follows. Launch arguments are read via `LaunchArgs`.
One missed call would mean the sandbox writes into real settings.

⚠️ **`@AppStorage` is only safe inside a `View`.** Inside a class it always
writes to `UserDefaults.standard` — `.defaultAppStorage` lives in the
SwiftUI environment and never reaches a plain object. `ThemeStore` was
written that way and leaked palette/panel surface/material into real
settings from the sandbox (found 2026-08-11). Non-View types must go
through `EmbarDefaults.store` directly. `DefaultsIsolationGuardTests`
scans the sources for both mistakes — a unit test cannot catch them,
because in tests both stores are the same object.

- **Bundle ID:** `nechai.Embar` · **Swift:** 5.0 · **Deployment target:** macOS 14.0
- **Supported platforms:** iOS, macOS, xrOS. Primary target is **macOS** (a side panel); iOS/visionOS are template artifacts, not planned surfaces.
- **App Sandbox is ON from the first build** — every new entitlement is a deliberate decision (see below).

## Architecture (what to build)

Embar is **one pipeline, not three tabs**: a quiet side panel with three capture surfaces plus a Home screen, all sharing a single SwiftData store. The surfaces link to each other — that connective tissue is the product.

- **Stickies** — fleeting quick-capture notes (color, deadline, reminder, folder, pin, auto-archive).
- **Reader** — annotation layer *over* what you read (it links to the source, never renders it). Entries typed as Thought / Quote / Question / Insight / Voice; highlights, `#tags`, favorites, search.
- **Notes** — the "sink" where thoughts mature: full notes, folders, pin, `[[title]]` backlinks, nested notes.
- **Home** — day-at-a-glance shutter: weekly ring strip, day timeline with lane-packing, todos (folder carousel), habits (streaks + daily reset).

**Cross-surface links** are the core mechanic, not a feature: Sticky→Note (`matureSticky`, bidirectional id link), Sticky→Todo, Reader entry→Note, nested notes, backlinks. Model these as real relationships.

### Frameworks
- **SwiftUI** — UI foundation.
- **AppKit** — the side-panel shell: an `NSPanel` (`.canBecomeKey`, `.floating`) that slides from the screen edge on hover/hotkey, auto-hides on focus loss, with a lock mode. This is the defining platform integration.
- **SwiftData** — single source of truth for local storage (not Core Data).
- Later: **CloudKit** (iCloud sync), **WidgetKit** (sticky widgets), **NSAttributedString** (rich note text), **PDFKit** (possible Reader sources).

### Data-model rules (apply from the very first model)
The schema must be **CloudKit-compatible from day one** even though sync ships in Milestone 6:
- Every property **optional or with a default value**.
- **No `@Attribute(.unique)`**.
- Relationships must declare an **inverse**.
- **Soft-delete**: `deletedAt: Date?`, purge physically after 30 days — never hard-delete user data.
- In-session undo stack in memory (⌘Z).

## Scrolling rule (project-wide)

No visible scroll indicators anywhere — every ScrollView/List gets `.scrollIndicators(.hidden)` (the prototype hides scrollbars too). Never use blanket `.transaction { $0.animation = nil }` — it mutes ancestors' surface transitions and children's animations; use value-scoped `.animation(nil, value:)` instead.

## Motion rule (project-wide, SPEC §7.2-A)

Animate ONLY real moving surfaces: panel slide, Home shutter, sticky appear/disappear, bottom sheets, expanded editors/event modal, toasts, toggles, hover-lift, tab underline slide (all from the prototype), and **card reorder caused by a direct user action on the card** (done/pin/create/undo — `EmbarMotion.settle`, no springs; Reduce Motion = instant; see SPEC §15.62). **Everything else is INSTANT**: tab content, texts/counters, filters/chips/folders, week-day selection, list updates/sorting driven by filters or the system, palette switching. No implicit `.animation(...)` on containers and no `withAnimation` around non-surface state changes; use animation-less transactions for filtered lists.

## Ізольований deinit (міна рантайму — правило чинне, поки Apple не полагодить)

Проєкт зібрано з default isolation MainActor (дефолт шаблону Xcode 26) і
deployment target macOS 14. Наслідок: клас **без явного `deinit`** отримує
синтезований ІЗОЛЬОВАНИЙ deinit, а його back-deploy шлях у рантаймі
(`swift_task_deinitOnExecutor…` → `TaskLocal::StopLookupScope`) звільняє
чужий вказівник, коли останнє посилання відпускається всередині Swift
Task: `pointer being freed was not allocated`, зіпсована купа, далі
фриз/краш у довільному місці. Підтверджені жертви: `ToastCenter.UndoAction`
(блокер ⌘Z 2026-08-25), `NoteEditorModel` (блокер «⌘Z після видалення цілі
звʼязку» 2026-08-26), `StickyHeightEstimator` (краші в тестах 2026-08-18).

Правило: **кожен новий клас (крім `@Model`) отримує явний
`nonisolated deinit {}`** — явний deinit компілятор не ізолює (перевірено
по SIL). Особливо критично для класів, що вмирають при навігації: моделі
редакторів, координатори, контролери тимчасових вікон. Маленькі обгортки
замикань роби структурами. `@Model`-класи не чіпаємо — їх життєвим циклом
керує SwiftData, крашів за ними не зафіксовано. Мінімальний репро для
Apple Feedback лежить у `docs/apple-feedback/`.

## Design system

Full spec in `docs/Embar.md` §9 and the two HTML files. Highlights to preserve when porting to SwiftUI:

- **Typography:** `Inter` for all UI (weights 300–600); `Fraunces` (incl. italic, optical size 9–144) for character moments — note/book titles, Reader dividers, section headings, Home hero month/day. Bundle both fonts (SIL OFL).
- **Palettes:** 15 named palettes (see §9.2 table). Each defines 5 sticky colors + 1 accent, swapped globally. In the prototype these are `.palette-<slug>` body classes over CSS vars — port to a Swift palette system (e.g. a `Color` extension / theme environment). Palette drives sticky colors, accents, progress rings, timeline event colors, and the pin decorator (Cream keeps its original red-pink pin). **Reader highlight colors are fixed** (yellow/purple/blue/red) and do *not* follow the palette.
- **Base tokens** (§9.3–9.5): scene bg `#e8e4df`; panel `#fcfbf9` radius 30px; cards `#fff` radius 18px; sticky radius 13px. Shadows and radii are enumerated — match them.
- **Reds — two roles, two tokens** (SPEC §15.53, revision 2026-08-17): `EmbarColors.brandRed` `#FE3B43` is identity only (header mark, onboarding buttons, gear halo, app icon, and Cream's palette accent); `EmbarColors.danger` `#c0392b` is function only (delete, deadlines, input errors, recording dot). Never introduce a third red, and never paint a destructive action in the brand color. The brand value comes from the **raw pixels** of `logo-master/logoColor.png` — a color-managed `NSImage` read reports `#FF5554` and that is how a wrong red once entered the code.
- **Nothing visual comes from macOS settings** (SPEC §15.54): text selection is warm graphite `#26241f` (14% where we draw, flattened `#DEDDDA` where the system draws — never a hue, a pink selection would be mistaken for the red highlight `#f4c8c8`); the caret is brandRed 2pt. Three hard-won facts encode the mechanism — do not "simplify" any of them: (1) `AppleHighlightColor` and `AppleAccentColor="0"` go into the **volatile argument domain** from `EmbarApp.init` (`EmbarSelection.applyAppWide`) — memory-only, read first, works in the sandbox too; **never persist these keys** (a persisted version once leaked into real settings and only worked by accident). (2) The `AccentColor` asset alone is useless for most users — on macOS it applies only when the system accent is "Multicolor"; an explicit user accent always wins, which is why the caret followed the system until the field-editor fix. (3) TextFields are edited by the window's **field editor**, not the visible view — `windowWillReturnFieldEditor` on `PanelController`/`DesktopStickyController` returns `EmbarFieldEditor` (brand caret); any new window class with text fields needs the same one line. Selection geometry hugs the font box (`EmbarTextView.drawSelection`, `PenTextView.drawSnugSelection`) because the full line box includes `lineHeightMultiple` slack. A UI affordance must never be hardcoded to one palette's accent either — that was the ochre `#c97a3a` bug.
- **Icons:** line-based SVG equivalents, `stroke-width 1.8`, round caps/joins, `currentColor`. **No emoji as icons** except the sticky pin (planned SVG) and the habit streak 🔥.

## Security & sandbox posture (non-negotiable)

From `docs/Embar.md` §12 — enforce these:
- **No network entitlements in v1.** CloudKit works through the system daemon and needs none; add nothing until sync lands.
- Request permissions **lazily**, at first use of the feature: notifications (sticky reminders), microphone (Reader voice memos), user-selected files read-only (photo attachments — copies live in the container).
- All data stays inside the app container. **No secrets in code** — Keychain only if ever needed.
- Run `/security-review` before every milestone release.

## Roadmap

`docs/Embar.md` §14 defines Milestones 1–7 (Foundation → Stickies → Home → Notes → Reader → Advanced/sync → Polish) and §11 lists what was deliberately left out of the prototype to be done natively in code (habit daily-reset/persistence, drag interactions, NSAttributedString paste normalization, Reader section dividers, dark mode + Liquid Glass, widgets, backlinks/nested notes). Commit after each milestone.

## Voice & tone (for any user-facing copy)

Warm, calm, human — a thoughtful companion, never a productivity drill sergeant. Plain language outward, smart architecture inward: **never** say "Zettelkasten" or "PKM" to users — say "thoughts find each other." Reassuring, a little literary.
