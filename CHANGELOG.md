# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the version is below `1.0.0`, minor releases may contain breaking changes
to the configuration format. Any such change ships with a migration path in
`ConfigStore`.

## [Unreleased]

### Fixed — gestures never worked at all

- **The touch reader leaked its devices and received nothing.**
  `MTDeviceCreateList` follows the Create rule, so the returned array *owns* the
  device objects — but it was a local variable in `MultitouchReader.start()`,
  released the moment that method returned. The devices were deallocated while
  `deviceRefs` still held raw pointers into them, so the contact-frame callback
  was registered against freed objects and never fired.

  The symptom was maximally misleading: `dlopen` succeeds, every symbol resolves,
  `MTDeviceStart` succeeds, `MTDeviceIsRunning` returns `true`, the framework
  prints its own device-recognition lines — and zero frames arrive, silently.
  This was present in the very first version of the reader, which means gestures
  have never worked in any build.

  The array is now held for the reader's lifetime and each device is retained
  individually, with both released in `stopReading()`. Verified against real
  hardware: 306 frames and 291 with fingers in a 15-second controlled run.

- **`fn` was being recorded into shortcuts and posted back.** macOS sets the
  `function` flag on arrow keys and F-keys whether or not the user pressed fn.
  Recording ⌃↑ for Mission Control stored `control + fn`, and posting fn back
  alongside the arrow key stopped the shortcut matching. `fn` is now excluded
  from `ShortcutModifiers.displayable`, and `ActionExecutor` filters modifiers
  through it when posting, so configs recorded before this fix are repaired
  without re-recording. `showDesktop` moved from `fn+F11` to plain F11 as a
  consequence.

- **Switching an action's type left the old parameters behind.** A binding
  changed from Keyboard Shortcut to Middle Click kept its `keyCode` and
  `modifiers` in the JSON — inert at runtime, but confusing in a file people are
  invited to hand-edit. `ActionConfig.switchingType(to:)` now keeps only the
  parameters the new type uses, while re-selecting the same type stays a no-op so
  a just-recorded shortcut survives.

### Added — reader diagnostics

- **A `frames` counter in the status bar**, orange while zero. Distinguishing
  "the reader is dead" from "a threshold is wrong" previously required attaching
  a debugger; it is now visible at a glance, and it is the first thing to check
  when a gesture doesn't fire.

### Verified against real hardware

First real-device validation, on a Magic Mouse and a built-in trackpad under
macOS 26.4:

- **The reverse-engineered `MTFinger` layout is correct** — `state=3` on contact,
  normalized position `(0.7103, 0.6803)`, size `0.875`. This was the project's
  largest open question.
- **Device classification is correct** — family 112 external → Magic Mouse,
  family 106 built-in → Built-in Trackpad.
- **Known issue not yet addressed:** a single finger resting on the mouse while
  you move it produces continuous `1-finger Hold` and `1-finger Swipe`
  recognitions. One finger on a mouse is just *using* the mouse, so single-finger
  gestures need either a minimum finger count or to be off by default.

### Changed — the window was rebuilt again

The Options+-style window shipped earlier in this cycle was confusing, and was
replaced rather than patched. What was wrong with it, and what replaced it:

- **Binding chips floated around a picture of the mouse.** Their position carried
  no information: Logi Options+ points each label at a real physical button, and
  the Magic Mouse has no buttons to point at, so the spatial metaphor was
  decorative and misleading. The device illustration is gone.
- **Bindings were split across two screens** — taps, holds and clicks on one,
  swipes on another — with nothing on either screen indicating the other
  existed. There is now **one sidebar listing every binding**, grouped by gesture
  kind with counts, and searchable.
- **The theme was hardcoded dark**, ignoring system appearance and looking
  foreign next to other Mac apps. The window now uses semantic colours and
  follows light/dark automatically.
- **A panel titled "Actions" also contained the gesture pickers**, mixing "which
  gesture" with "what it does". The detail pane now has three clearly separated
  sections: **Gesture**, **Action**, and **Runs On**.
- Settings moved into their own sidebar entries (Devices, Tuning, About) instead
  of hiding behind an unlabelled toolbar icon.
- The detail pane warns when another enabled binding claims the same gesture on
  an overlapping device, since only the first match ever runs.

### Added — multiple devices, including trackpads

- **Per-device enable switches.** A **Devices** page lists every attached
  multitouch device with the family ID, built-in flag, and sensor dimensions used
  to identify it — worth quoting if a device is misclassified. Devices that
  aren't attached can be configured ahead of time.
- **Per-binding device scope.** Each binding has a **Runs On** section, so a
  4-finger tap can be Magic Mouse only while a swipe works on the trackpad too.
  The same gesture can even do different things on different devices. Switching a
  device off in Devices overrides every per-binding scope.
- **Device identification** via `MTDeviceGetDeviceID`, `MTDeviceGetFamilyID`,
  `MTDeviceIsBuiltIn` and `MTDeviceGetSensorSurfaceDimensions`. Each accessor is
  resolved individually and tolerated as missing, so losing one to a macOS update
  degrades classification rather than breaking gestures. Unknown devices fall
  back to a surface-aspect heuristic — a mouse surface is taller than wide, a
  trackpad wider than tall — rather than being ignored.
- **Trackpads default to off.** macOS already binds three- and four-finger
  trackpad gestures to Mission Control, Look Up, and drag; claiming those on
  install would break the machine for anyone who tried this. Enabling a trackpad
  also does **not** suppress the system gesture — both fire — which the Devices
  page says plainly.

### Fixed — devices were being confused for each other

- **Frames from different devices were fed into one shared recognizer.** On a Mac
  with both a Magic Mouse and a trackpad, the two devices interleave frames, so
  one device's touches could start a gesture session the other device's touches
  then finished — producing gestures nobody made. There is now **one recognizer
  per device**, and each frame is tagged with its source.
- **Trackpad gestures fired bindings whether you wanted them to or not.** Every
  device was started and the callback ignored which device sent the frame, so a
  3-finger tap on a laptop trackpad triggered the middle-click binding silently.
  Devices are now opt-in.

### Known limitation

- **Click gestures can't be reliably attributed to a device.** `CGEvent` carries
  no device identity, so a click is attributed to whichever device last reported
  contact, falling back to the first non-trackpad device. Scoping a click binding
  to a specific device is therefore best-effort.

### Added — sharing test builds

- **Universal builds.** `./Scripts/build_app.sh --universal` produces an
  arm64 + x86_64 binary. Builds were previously arm64-only, so they would not
  launch at all on an Intel Mac. `swift build --arch` needs full Xcode's
  xcbuild, so each slice is built with `--triple` and combined with `lipo`,
  which works with Command Line Tools alone.
- **`Scripts/package_release.sh`** — universal build, zip via `ditto` so the
  code signature survives, plus a SHA-256 checksum, and it prints the
  `gh release create --prerelease` command to publish it. Warns before packaging
  a dirty working tree, since testers would report against a build that can't be
  reconstructed from a commit.
- **Version stamping.** A root `VERSION` file is the single source of truth;
  the build script writes it into `CFBundleShortVersionString`, uses the commit
  count as `CFBundleVersion`, and records the short git SHA (with a `-dirty`
  suffix when applicable) in a `MagicBindGitSHA` key. The Settings screen shows
  all three, selectable, so a bug report can pin the exact build.
- **[docs/TESTING.md](docs/TESTING.md)** — a guide to hand to testers: both
  install paths, the `xattr -dr com.apple.quarantine` step a downloaded zip
  needs, what's most worth testing (starting with whether the reverse-engineered
  touch data works on their machine at all), and what to include in a report.

### Fixed — bundle identity

- **The bundle identifier was `com.example.magicbind`**, a placeholder. It is now
  `io.github.kshitij-shringi.magicbind`. macOS keys Accessibility permission off
  the bundle identifier, so a placeholder is both wrong and a real collision
  risk. **Existing users must re-grant Accessibility** after this change: remove
  MagicBind from System Settings → Privacy & Security → Accessibility and re-add
  it.
- `CFBundleVersion` and `CFBundleShortVersionString` claimed `1.0` on a pre-1.0
  project. They are now stamped at build time.

### Added — Options+-style interface

- **Rebuilt the window** in the style of Logi Options+: a dark canvas with a
  device illustration in the middle, each binding shown as a chip arranged
  around it, and a searchable Actions panel down the right-hand side. Selecting
  a chip and picking an action is the whole interaction — no separate list and
  detail pane.
- **Actions panel** with a search field and collapsible Recommended / System /
  Other groups, radio-button rows, and an inline editor that appears beneath
  whichever row needs more input (the shortcut recorder, a bundle identifier, a
  command). Search matches titles *and* the shortcut glyphs in subtitles, so
  typing `⌘V` finds Paste, and matched groups expand even when collapsed by
  default.
- **A "Custom gestures" screen** laying swipes out by direction around the
  device, one finger count at a time, with unassigned directions creating the
  binding when clicked.
- **20 named system actions** — Mission Control, Application Windows,
  Show/Hide Desktop, Desktop Left/Right, Maximize Window, Switch Application,
  Lock Screen, Screen Capture, Capture Region, Copy, Paste, Cut, Undo, Redo,
  Back, Forward, Volume Up/Down, Mute — so binding Mission Control no longer
  means knowing it's ⌃↑. Volume and mute post media keys rather than key codes.
- **The device illustration is a vector drawing**, not Apple's product
  photography, which isn't ours to redistribute. It shows finger dots matching
  the selected gesture's finger count.
- **A "Settings" screen** holding the recognizer thresholds, the mouse-button
  opt-in, and a Reveal in Finder button for the config file.
- **ACTIVE / INACTIVE badge** in the footer, clickable to toggle the engine.

### Added — new gesture kinds

- **Double tap**, with a tunable window (default 0.35s). Two taps of the same
  finger count within the window emit `.doubleTap`.
- **Click**, recognized per physical button (left, right, middle) and combined
  with however many fingers are resting on the surface — so "2-finger right
  click" is a binding. A bare click with no fingers is also valid, and displays
  without a finger prefix.
- `MouseButtonMonitor`, a **listen-only** `CGEvent` tap that makes click
  recognition possible. Touch frames carry no button state, so there is no other
  way. It is **off by default**, opt-in via `mouseClicksEnabled`, reads only the
  button number, and passes every event through unmodified.

### Changed

- **`SECURITY.md` no longer claims MagicBind never observes input.** That was
  true before click support and would have been false after it. The new
  disclosure describes exactly what the tap sees, what it cannot do, and what
  you're trusting — and the "nothing leaves your device" guarantee is unchanged.
- A click now suppresses the tap that would otherwise fire when the fingers
  lift, and clears any pending double tap. Clicking is not tapping.

### Fixed

- **Recording a keyboard shortcut failed for key equivalents.** The recorder
  used `NSEvent.addLocalMonitorForEvents`, which never sees combinations the
  main menu claims — ⌘W, ⌘Q, ⌘, and others were silently dropped. It is now a
  first-responder `NSView` overriding `performKeyEquivalent(with:)`, which sees
  them first. This is the approach every working macOS shortcut recorder uses.
- Selecting a catalog row that needs input no longer discards parameters already
  entered, so re-selecting "Keyboard Shortcut" doesn't wipe the shortcut you
  just recorded.

### Added — earlier in this cycle

- Live keyboard shortcut capture in the binding editor. Click the shortcut
  field, press the combination you want, and it records the key code and
  modifiers — replacing the raw virtual-key-code and `CGEventFlags` number
  fields. Escape cancels, Delete clears, and while armed a local event monitor
  swallows key events so ⌘Q records rather than quitting. (Phase 4, item 1.)
- `ShortcutModifiers` and `KeyboardShortcutFormatter` in `MagicBindCore`, which
  render a key code and modifier set as the string a person recognizes ("⇧⌘4",
  "⌃␣", "F5"). Key labels resolve against the user's **current keyboard
  layout** via `UCKeyTranslate`, so an AZERTY or Dvorak user sees the key they
  actually pressed rather than a US-ANSI guess. Modifier glyphs use Apple's
  menu ordering (fn ⇪ ⌃ ⌥ ⇧ ⌘).
- The bindings list now summarizes each action instead of only naming its type
  — a keyboard-shortcut binding shows its shortcut, a launch-app binding shows
  its bundle identifier.
- 15 more tests, covering modifier glyph ordering, that `ShortcutModifiers` raw
  values still match `CGEventFlags`, special-key glyphs, and that the
  numeric-pad flag macOS sets on arrow keys is excluded from display.

### Fixed

- Selecting a different binding while a shortcut field was recording could
  capture the next keypress into the newly selected binding. The editor is now
  keyed by binding identity, so switching selection tears down the recorder.

The parity table in README.md tracks what's built and what isn't.

## [0.1.0] - 2026-08-10

Initial scaffold. The full pipeline exists and the pure-logic parts are tested,
but the recognizer has never been calibrated against a real device — treat this
as a foundation to build on, not a release to rely on.

### Added

**Core gesture pipeline** (`MagicBindCore`)

- `MultitouchReader` — binds to Apple's private
  `MultitouchSupport.framework` at runtime via `dlopen`/`dlsym`, so a missing or
  renamed symbol surfaces a `ReaderError` instead of crashing on launch.
  Registers a contact-frame callback and streams frames out.
- `MultitouchTypes` — Swift mirrors of the reverse-engineered `MTFinger`,
  `MTPoint`, `MTReadout` layouts and the `MTFingerState` lifecycle enum.
- `GestureRecognizer` — classifies frames into `tap`, `hold`, and four swipe
  directions, for 1–5 fingers. Takes frame timestamps as parameters rather than
  reading a clock, which keeps it fully unit-testable. Re-baselines the touch
  centroid when the contact count changes, so fingers landing one at a time
  aren't misread as a swipe. Emits at most one gesture per contact session.
- `GestureEngine` — wires reader → recognizer → binding lookup → executor, and
  hops to the main queue before running an action.
- `ActionExecutor` — five action types: `middleClick`, `keyboardShortcut`,
  `launchApp`, `shellCommand`, `appleScript`. Checks Accessibility trust before
  posting synthetic events and reports a readable error when it's missing.
- `ConfigStore` — loads and saves `AppConfig` as pretty-printed, sorted-key
  JSON at `~/Library/Application Support/MagicBind/config.json`. Treats a
  missing file as a first launch, and rejects configs written by a newer build
  rather than silently dropping fields.
- Models — `GestureSpec`, `GestureKind`, `GestureBinding`, `ActionConfig`,
  `ActionType`, `RecognizerTuning`, `AppConfig`, all `Codable`.
- Default bindings: **3-finger tap → middle click** and **4-finger tap →
  screenshot region** (⌘⇧4).

**Menu bar app** (`MagicBind`)

- Menu-bar-only app (`LSUIElement`) with enable/disable, Preferences, and Quit.
- Preferences window with a **Bindings** tab (list, add, remove, per-binding
  editor for gesture, finger count, and action parameters) and a **Tuning** tab
  exposing every recognizer threshold as a live slider, so thresholds can be
  calibrated without a rebuild.
- Status row showing whether the engine is running and the last recognized
  gesture — enough to tell whether the pipeline is alive.
- Requests Accessibility permission on launch and surfaces failures in the
  preferences window instead of failing silently.

**Repository foundation**

- `LICENSE` — MIT.
- `README` — feature-parity table against Logi Options+, install and permission
  documentation, prior-art credits to MiddleClick, Mac Mouse Fix, and
  BetterTouchTool.
- `CONTRIBUTING.md` — build steps, branch naming, Conventional Commits, PR
  review process, architecture orientation.
- `CODE_OF_CONDUCT.md` — Contributor Covenant 2.1.
- `SECURITY.md` — private-framework and Accessibility risk disclosure, the
  no-telemetry / nothing-leaves-the-device guarantee, and private reporting
  instructions.
- `Tests/MagicBindCoreTests` — 23 XCTest cases covering `GestureRecognizer`
  (synthetic `MTFinger` frames for taps, all four swipe directions, holds,
  session lifecycle, and non-contact rejection) and `ConfigStore` (Codable
  round-trips, disk round-trips, corrupt input, version rejection, migration,
  binding lookup).
- `.swiftlint.yml` — SwiftLint config; CI runs it with `--strict`.
- GitHub Actions CI — `swift build`, `swift test`, and SwiftLint on
  `macos-latest` for every push and pull request.
- Issue templates for bug reports and feature requests, plus a pull request
  template.
- `Scripts/build_app.sh` — wraps the SwiftPM executable into a signed
  `MagicBind.app` bundle so macOS will grant it Accessibility permission.

### Known limitations

- Recognizer thresholds are unvalidated estimates, not measurements. Expect
  false triggers and missed gestures until they're calibrated.
- The `MTFinger` struct layout is reverse-engineered and unverified across macOS
  versions. A wrong layout produces garbage coordinates.
- Keyboard shortcut bindings require raw virtual key codes; there is no live
  "press a key to record" capture yet.
- No per-app profiles, pointer/scroll settings, auto-update, or notarized
  release.
- Not sandboxed, by necessity — no Mac App Store distribution.


[Unreleased]: https://github.com/Kshitij-Shringi/magicbind/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kshitij-Shringi/magicbind/releases/tag/v0.1.0
