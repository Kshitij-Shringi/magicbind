# MagicBind

[![CI](https://github.com/Kshitij-Shringi/magicbind/actions/workflows/ci.yml/badge.svg)](https://github.com/Kshitij-Shringi/magicbind/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](#requirements)
[![Swift 5.9](https://img.shields.io/badge/swift-5.9-orange.svg)](https://swift.org)

**An open-source gesture manager for the Apple Magic Mouse and Magic Trackpad.**
Bind any N-finger tap, double tap, click, hold, or swipe to any action — a
system action like Mission Control or Screen Capture, a keyboard shortcut you
record by pressing it, launching an app, a shell command, or an AppleScript.

> [!WARNING]
> **MagicBind is pre-1.0 and unvalidated on real hardware.** The architecture is
> in place and the logic is tested, but the recognizer thresholds are untested
> guesses that need calibration against real hardware, and the reverse-engineered
> `MTFinger` struct layout is unverified on your specific macOS version. See
> [Status](#status) before installing. Contributions very welcome.

## What this is

Buy a Logitech MX Master and you get [Logi Options+][logi]: button remapping,
gesture buttons, per-app profiles, pointer tuning. Buy Apple's own Magic Mouse
and you get three checkboxes in System Settings.

The touch surface on a Magic Mouse can sense five fingers. macOS uses almost
none of that. MagicBind is an attempt to close that gap with something free,
open, auditable, and local — no account, no cloud, no telemetry.

[logi]: https://www.logitech.com/en-us/software/logi-options-plus.html

## Feature parity vs Logi Options+

Where MagicBind stands against what an MX Master owner gets. This is a roadmap
as much as a comparison — most rows are not built yet.

| Capability | Logi Options+ (MX Master 3) | MagicBind (Magic Mouse) | Status |
|---|---|---|---|
| Button remapping | Remap physical buttons | Gesture → action mapping (the Magic Mouse has no discrete buttons beyond click) | ✅ v0.1 |
| Action library | Fixed catalog of actions | 20 named system actions (Mission Control, Screen Capture, Desktop left/right, Maximize, Lock, Volume, Copy/Paste/Undo/Redo, Back/Forward) plus middle click, custom shortcut, launch app, shell command, AppleScript | ✅ v0.2 |
| Gesture button | Hold a button + move the mouse | N-finger swipes (up/down/left/right), taps, double taps, holds, and clicks — 1–5 fingers | ✅ v0.2 |
| Physical button clicks | Remap left/right/middle | **Click** gestures per button, with or without fingers resting on the surface (opt-in) | ✅ v0.2 |
| Config storage | Cloud-synced account | Local hand-editable JSON, git-friendly, syncable via any folder-sync tool | ✅ v0.1 |
| Shortcut recording | Press a key to record it | Click the field, press the shortcut — rendered as ⇧⌘4, resolved against your keyboard layout | ✅ v0.1 |
| Preferences UI | Polished, with animations | Options+-style dark UI: device illustration with bindings arranged around it, searchable Actions panel, directional gesture screen | ✅ v0.2 |
| Pointer speed / acceleration | Sliders | Planned — [Phase 5][plan] | ❌ Planned |
| Scroll direction & smooth scroll | Sliders and toggles | Planned — [Phase 5][plan] | ❌ Planned |
| Per-app profiles | Auto-switching per app | Planned — [Phase 6][plan] | ❌ Planned |
| Onboarding wizard | Guided first run | Planned — [Phase 7][plan] | ❌ Planned |
| Auto-update | Built in | Planned, via Sparkle — [Phase 7][plan] | ❌ Planned |
| Homebrew install | — | Planned — [Phase 7][plan] | ❌ Planned |
| Telemetry | Collects usage data | **None, by design** | ✅ Never |
| Price | Free, closed source, account-based | Free, MIT, no account | ✅ |

[plan]: ProjectPlan.md

## How it works

```
MultitouchReader    dlopen's Apple's private MultitouchSupport.framework,
      |             emits raw touch frames
      v
GestureRecognizer   turns frames into discrete tap / double tap / hold /
      |             swipe GestureSpecs
      |             ← MouseButtonMonitor adds clicks (opt-in, listen-only tap)
      v
GestureEngine       looks up a matching GestureBinding in ConfigStore
      |
      v
ActionExecutor      fires the action via CGEvent / NSWorkspace / AppleScript
```

Config lives in plain JSON at
`~/Library/Application Support/MagicBind/config.json`, so you can hand-edit
bindings, keep them in a dotfiles repo, or diff them.

Out of the box: **3-finger tap → middle click**, and **4-finger tap →
screenshot region** (⌘⇧4).

## Requirements

- macOS 13 (Ventura) or later
- A Magic Mouse or Magic Trackpad
- Xcode 15+ to build (Command Line Tools alone can build, but not run the tests)

## Install

No prebuilt release yet — there's no signed, notarized binary to hand you, and
[you shouldn't run an unsigned Accessibility app someone else built](SECURITY.md#not-sandboxed-and-why).
Build it yourself; it takes about a minute.

```sh
git clone https://github.com/Kshitij-Shringi/magicbind.git
cd magicbind
./Scripts/build_app.sh
open build/MagicBind.app
```

`build_app.sh` compiles a release build, wraps it into a proper
`MagicBind.app` bundle, and ad-hoc signs it. The bundle matters: macOS grants
Accessibility permission per bundle identifier, and the menu-bar-only behavior
comes from the bundle's `Info.plist`.

MagicBind runs as a menu bar item with no Dock icon. Choose **Open MagicBind…**
from the menu bar to edit bindings.

<details>
<summary>Building without the app bundle</summary>

```sh
swift build -c release    # binary at .build/release/MagicBind
swift build               # debug
open Package.swift        # or work in Xcode
```

Running the bare executable is fine for compile-checking, but Accessibility
permission won't stick reliably, so gestures won't fire. Use the `.app`.

</details>

Homebrew cask and notarized releases are [Phase 7][plan].

## Permissions, and why each is needed

MagicBind asks for the following. All are load-bearing, and none send data
anywhere.

| Permission | Why it's required | What happens without it |
|---|---|---|
| **Accessibility**<br>*System Settings → Privacy & Security → Accessibility* | Posting a synthetic middle click or keystroke through `CGEvent` is privileged. This is how a bound action actually reaches the app you're using. | The app runs and recognizes gestures, but every action silently fails. |
| **Automation / Apple Events**<br>*prompted on first use* | Only for `appleScript` actions. Requested lazily, per target app, by macOS itself. | AppleScript bindings fail. Everything else works. |
| **Mouse button watching**<br>*opt-in, Settings tab* | Only for **Click** gestures. Touch frames carry no button state, so recognizing a click needs a listen-only `CGEvent` tap. **Off by default.** | Click gestures don't fire. Taps, holds, double taps, and swipes all work normally. |

You'll be prompted for Accessibility on first launch. Grant it, then **relaunch
the app** — macOS doesn't extend the permission to an already-running process.

> [!NOTE]
> Accessibility is a broad permission, and you should be skeptical of anything
> that asks for it. MagicBind posts only the events your bindings ask for, in
> [ActionExecutor.swift](Sources/MagicBindCore/ActionExecutor.swift) — the only
> file that posts a `CGEvent`. Read it; it's about 200 lines.
>
> If you enable Click gestures, MagicBind additionally *observes* mouse button
> events through a **listen-only** tap that reads one field — the button number —
> and cannot modify or suppress your clicks. That's
> [MouseButtonMonitor.swift](Sources/MagicBindCore/MouseButtonMonitor.swift), and
> [SECURITY.md](SECURITY.md#risk-disclosure-mouse-button-watching) spells out the
> tradeoff. Leave the setting off if you'd rather not grant that.

MagicBind is **not sandboxed** and cannot be: the App Sandbox blocks both the
private framework and `CGEvent` posting. That rules out the Mac App Store.
Details in [SECURITY.md](SECURITY.md).

## Status

**What works:** the pipeline is complete end to end, the pure-logic parts are
covered by 75 tests, and the UI can add, edit, and delete bindings for every
gesture kind.

**What to be skeptical about:**

- **Recognizer thresholds are guesses.** `tapMaxDuration`, `swipeMinMovement`
  and friends in [Models.swift](Sources/MagicBindCore/Models.swift) were chosen
  by reasoning, not measurement. Expect false triggers or missed gestures until
  they're calibrated. They're exposed in the Settings tab so you can adjust them
  without rebuilding.
- **The `MTFinger` struct layout is reverse-engineered.** It mirrors the
  commonly documented shape of Apple's private struct. If it's wrong for your
  macOS version, you'll get garbage coordinates. Validating this against real
  frames is [Phase 2][plan] and the highest-value thing a contributor could do.
- **Private frameworks break.** Apple can change or remove
  `MultitouchSupport.framework` symbols in any update, and historically has.
  MagicBind resolves them at runtime, so it degrades to "gestures stop working"
  rather than crashing — but budget for maintenance.
- **Shortcut recording swallows keys while armed.** While the shortcut field is
  recording it consumes key events, so ⌘Q records instead of quitting. Escape
  cancels, Delete clears, and clicking elsewhere disarms it.
- **A double tap fires `Tap` first, then `Double Tap`.** Suppressing the first
  tap would mean delaying *every* tap by the double-tap window, which makes
  single taps feel laggy. So bind one or the other, not both — unless you want
  both to run.
- **Click gestures need the opt-in tap.** They're inert until you enable "Watch
  physical mouse buttons" in Settings; the UI says so on the gesture itself.
- **The device illustration is drawn, not photographed.** It's a vector
  approximation, because shipping Apple's product photography in an
  MIT-licensed repo isn't ours to do.

The full phase-by-phase plan is in [ProjectPlan.md](ProjectPlan.md).

## Prior art and credits

MagicBind did not appear from nowhere. These projects mapped the territory
first, and it's worth using them if they fit your needs better:

- **[MiddleClick](https://github.com/artginzburg/MiddleClick)** by
  [@artginzburg](https://github.com/artginzburg) — three-finger tap → middle
  click, and nothing else. Focused, actively maintained, and the reference for
  how to talk to `MultitouchSupport.framework` at all. **If a middle click is
  all you need, use MiddleClick — it's more mature than this.**
- **[Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix)** by
  [@noah-nuebling](https://github.com/noah-nuebling) — a far richer
  button→action mapping engine with a genuinely polished preferences UI, and the
  model this project's action mapping is shaped after. It deliberately targets
  standard USB/Bluetooth mice and **does not support the Magic Mouse**, which is
  the specific gap MagicBind exists to fill.
- **[BetterTouchTool](https://folivora.ai)** by Andreas Hegenberg — the paid,
  closed-source product that does all of this and much more, extremely well. If
  you want something that works today and don't mind paying, buy BTT.
- The broader reverse-engineering of Apple's multitouch API, documented over
  years across projects like [`mtrack`](https://github.com/dhruvbird/mtrack),
  `fingermgmt`, and many blog posts. The `MTFinger` layout here descends from
  that shared work.

## Contributing

Contributions are welcome — see **[CONTRIBUTING.md](CONTRIBUTING.md)** for build
steps, branch naming, Conventional Commits, and how review works.

Fastest ways to help:

1. **Validate the touch data on your Mac** ([Phase 2][plan]) — this unblocks
   everything else.
2. **Add SF Symbol icons per action type** to the bindings list.
3. **Report what breaks** on your hardware and macOS version.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md). Security issues go
through [SECURITY.md](SECURITY.md), privately — not a public issue.

## License

[MIT](LICENSE) © 2026 Kshitij Shringi

Do whatever you want with it. If you ship something built on this, a link back
is appreciated but not required.
