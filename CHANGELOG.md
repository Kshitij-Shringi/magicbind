# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the version is below `1.0.0`, minor releases may contain breaking changes
to the configuration format. Any such change ships with a migration path in
`ConfigStore`.

## [Unreleased]

Nothing yet. See [ProjectPlan.md](ProjectPlan.md) for what's planned next —
Phase 2 is validating the reverse-engineered touch data against real hardware.

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
  false triggers and missed gestures until [Phase 2/3][plan] calibration.
- The `MTFinger` struct layout is reverse-engineered and unverified across macOS
  versions. A wrong layout produces garbage coordinates.
- Keyboard shortcut bindings require raw virtual key codes; there is no live
  "press a key to record" capture yet.
- No per-app profiles, pointer/scroll settings, auto-update, or notarized
  release. See [ProjectPlan.md][plan].
- Not sandboxed, by necessity — no Mac App Store distribution.

[plan]: ProjectPlan.md

[Unreleased]: https://github.com/Kshitij-Shringi/magicbind/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kshitij-Shringi/magicbind/releases/tag/v0.1.0
