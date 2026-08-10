# Contributing to MagicBind

Thanks for looking. MagicBind is small and early, which means almost anything
you touch will matter — and also that conventions here are still cheap to
change if you have a better idea.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Table of contents

- [Getting set up](#getting-set-up)
- [Building and running](#building-and-running)
- [Tests](#tests)
- [Linting](#linting)
- [Branch naming](#branch-naming)
- [Commit messages](#commit-messages)
- [Pull requests](#pull-requests)
- [Architecture orientation](#architecture-orientation)
- [Good first contributions](#good-first-contributions)

## Getting set up

**Requirements**

| Tool | Version | Notes |
|---|---|---|
| macOS | 13.0 (Ventura) or later | The package targets `.macOS(.v13)`. |
| Xcode | 15 or later | **Required to run the tests** — see below. |
| Swift | 5.9 or later | Ships with Xcode. |
| SwiftLint | 0.55 or later | `brew install swiftlint` |
| A Magic Mouse or Magic Trackpad | — | Only needed for manual testing. |

> [!IMPORTANT]
> **Xcode, not just Command Line Tools.** `swift build` and SwiftLint work with
> Command Line Tools alone, but `swift test` does not: `XCTest` ships only with
> the full Xcode installation. If you see `error: no such module 'XCTest'`,
> install Xcode and point the toolchain at it:
>
> ```sh
> sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
> ```
>
> With Command Line Tools only, SwiftLint also needs to be told where
> `sourcekitd` lives:
>
> ```sh
> TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint
> ```

**Clone and build**

```sh
git clone https://github.com/Kshitij-Shringi/magicbind.git
cd magicbind
swift build
```

## Building and running

```sh
swift build                  # debug build
swift build -c release       # release build
open Package.swift           # open in Xcode instead

./Scripts/build_app.sh       # build + wrap into build/MagicBind.app
open build/MagicBind.app
```

**Run it from the `.app` bundle, not from `.build/`.** MagicBind needs
Accessibility permission, and macOS grants that per *bundle identifier* — a
bare executable can't be granted it reliably, and `LSUIElement` (the
no-Dock-icon behavior) only applies inside a bundle.
`Scripts/build_app.sh` handles the wrapping and ad-hoc signing.

After the first launch, grant Accessibility in System Settings → Privacy &
Security → Accessibility, then relaunch.

> [!NOTE]
> **Re-granting permission after a rebuild.** Ad-hoc signatures change on every
> build, so macOS may treat a rebuilt app as a new one and silently stop
> honoring the permission. If gestures quietly stop firing after a rebuild,
> remove MagicBind from the Accessibility list and re-add it.

## Tests

```sh
swift test                                    # everything
swift test --filter GestureRecognizerTests    # one suite
swift test --filter testThreeFingerTap        # one test
```

Tests live in [Tests/MagicBindCoreTests/](Tests/MagicBindCoreTests/) and use
XCTest.

**What we expect tests for.** `GestureRecognizer` and `ConfigStore` are pure
logic with no system dependencies, and they should stay that way — every
behavior change there wants a test. The recognizer takes its timestamps from
the caller precisely so tests can feed synthetic `MTFinger` frames and assert
on the emitted `GestureSpec` without sleeping or touching real hardware. Use
`MTFinger.contact(identifier:x:y:)` to build frames.

**What we don't unit test.** `MultitouchReader` and `ActionExecutor` touch real
system state — a private framework and the global event stream. Cover changes
there with manual verification and describe what you did in the PR.

## Linting

```sh
swiftlint            # check
swiftlint --fix      # autocorrect what can be autocorrected
swiftlint --strict   # what CI runs: warnings become errors
```

Config is in [.swiftlint.yml](.swiftlint.yml). CI runs `--strict`, so a warning
will fail your PR. If a rule is genuinely wrong for a piece of code, disable it
narrowly and say why:

```swift
// swiftlint:disable:next force_unwrapping - guarded by the check above
```

Prefer that over adding to `disabled_rules` in the config, which turns the rule
off for everybody.

## Branch naming

Branch off `develop`. Use `<type>/<short-description>`, matching the commit
types below:

```
feat/keyboard-shortcut-capture
fix/three-finger-tap-false-positives
docs/readme-permissions-section
chore/bump-swiftlint
refactor/extract-gesture-matching
test/recognizer-hold-edge-cases
```

Lowercase, hyphen-separated. If there's an issue, you may append the number:
`fix/tap-false-positives-42`.

**Branch structure**

| Branch | Purpose |
|---|---|
| `main` | Released, tagged code. Protected — only receives merges from `develop` or a hotfix branch. |
| `develop` | Integration branch. Default target for PRs. |
| `<type>/<description>` | Your work. Branch from `develop`, PR back into `develop`. |
| `hotfix/<description>` | Urgent fix branched from `main`, merged to both `main` and `develop`. |

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>(<optional scope>): <description>

<optional body>

<optional footer>
```

**Types**

| Type | Use for |
|---|---|
| `feat` | A new capability |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `test` | Adding or fixing tests |
| `refactor` | Behavior-preserving restructuring |
| `perf` | Performance work |
| `style` | Formatting, lint fixes, no logic change |
| `build` | Build system, `Package.swift`, scripts |
| `ci` | GitHub Actions and CI config |
| `chore` | Anything else — dependency bumps, housekeeping |

**Rules**

- Description in the imperative mood, lowercase, no trailing period:
  `fix: stop tap firing during scroll`, not `Fixed the tap bug.`
- Keep the subject line at 72 characters or less.
- Scope is optional but useful: `feat(recognizer):`, `fix(config):`.
- Breaking changes get a `!` and a footer:

```
feat(config)!: move bindings into named profiles

AppConfig.bindings is replaced by AppConfig.profiles. Configs from 0.1.x
are migrated on load.

BREAKING CHANGE: AppConfig.bindings no longer exists.
```

**Examples**

```
feat(ui): add live keyboard shortcut capture
fix(recognizer): re-baseline centroid when finger count changes
docs: explain why the app can't be sandboxed
test(config): cover migration from an unversioned file
chore: bump swiftlint to 0.57
```

## Pull requests

**Before you open one**

1. Branch from `develop`.
2. `swift build` succeeds.
3. `swift test` passes.
4. `swiftlint --strict` is clean.
5. Update [CHANGELOG.md](CHANGELOG.md) under `## [Unreleased]` if the change is
   user-visible. Skip it for pure refactors, tests, or internal docs.
6. Update the README or other docs if you changed behavior they describe.

**Opening it**

- Target `develop`, not `main`.
- Fill in the [PR template](.github/pull_request_template.md).
- Link the issue with `Closes #123`.
- Keep it focused. One logical change per PR — a 400-line PR doing three things
  gets reviewed slower than three PRs doing one thing each.
- Mark it a draft if you want early feedback.

**How review works**

1. **CI runs first** — `swift build`, `swift test`, and `swiftlint --strict` on
   `macos-latest`. Get it green before asking for review; a red PR usually
   won't get read.
2. **A maintainer reviews.** Expect first response within about a week. Nudge
   the PR if it's been longer — that's not rude, it's helpful.
3. **Review comments come in two flavors.** Anything phrased as a request needs
   resolving before merge; anything prefixed **nit:** is optional and you may
   decline it with a sentence of reasoning.
4. **Push follow-up commits** rather than force-pushing during review, so
   reviewers can see what changed. Squashing happens at merge.
5. **Approval, then merge.** One maintainer approval is enough. Maintainers
   squash-merge into `develop`; the squashed subject follows Conventional
   Commits, so a clean commit history makes for a clean changelog.

**Things that will get pushback**

- Behavior changes to `GestureRecognizer` or `ConfigStore` with no test.
- Recognizer threshold changes with no explanation of what device and gesture
  you measured. Numbers in that file need a story — see
  [ProjectPlan.md](ProjectPlan.md) Phase 2/3.
- New dependencies. This app has none on purpose. Bringing one in needs a
  reason that outweighs the cost of auditing it in something that holds
  Accessibility permission.
- Anything that sends data off the device. See [SECURITY.md](SECURITY.md) —
  "nothing leaves your machine" is a hard guarantee, not a default.
- Widening `disabled_rules` in `.swiftlint.yml` to make your code pass.

## Architecture orientation

```
MultitouchReader   dlopen's the private framework, emits raw touch frames
      |
GestureRecognizer  turns frames into discrete tap/swipe/hold GestureSpecs
      |
GestureEngine      looks up a matching GestureBinding in ConfigStore
      |
ActionExecutor     fires the action via CGEvent / NSWorkspace / AppleScript
```

| File | Responsibility |
|---|---|
| [MultitouchTypes.swift](Sources/MagicBindCore/MultitouchTypes.swift) | Reverse-engineered `MTFinger` / `MTPoint` layout. **Change carefully.** |
| [MultitouchReader.swift](Sources/MagicBindCore/MultitouchReader.swift) | Runtime binding to `MultitouchSupport.framework`. |
| [GestureRecognizer.swift](Sources/MagicBindCore/GestureRecognizer.swift) | Frames → gestures. Pure logic, fully testable. |
| [Models.swift](Sources/MagicBindCore/Models.swift) | `GestureSpec`, `GestureBinding`, `ActionConfig`, `AppConfig`. |
| [ConfigStore.swift](Sources/MagicBindCore/ConfigStore.swift) | JSON persistence and migration. |
| [KeyboardShortcut.swift](Sources/MagicBindCore/KeyboardShortcut.swift) | `ShortcutModifiers` + layout-aware shortcut formatting. Raw values must stay in sync with `CGEventFlags`. |
| [ActionExecutor.swift](Sources/MagicBindCore/ActionExecutor.swift) | The only file that posts `CGEvent`s. |
| [GestureEngine.swift](Sources/MagicBindCore/GestureEngine.swift) | Wires the pipeline together. |
| [Sources/MagicBind/](Sources/MagicBind/) | Menu bar app and SwiftUI preferences. |

Two rules worth internalizing:

- **`MagicBindCore` holds the logic; `MagicBind` holds the UI.** Anything
  testable belongs in Core.
- **`GestureRecognizer` must stay free of wall-clock time and of the private
  framework.** It takes timestamps as parameters. That constraint is what makes
  it testable — don't reach for `Date()` inside it.

Where the project is headed, phase by phase, is in
[ProjectPlan.md](ProjectPlan.md). Reading Phase 2 and 3 will save you from
proposing recognizer tuning that's already planned.

## Good first contributions

- **SF Symbol icons per `ActionType`** in the bindings list.
- **Import/export config** from the preferences window via
  `NSOpenPanel`/`NSSavePanel`.
- **Recognizer edge-case tests** — diagonal swipes, a finger lifting mid-swipe,
  a hold that drifts past `holdMaxMovement`.
- **Doc comments** on any public API in `MagicBindCore` that's missing one.

Questions are welcome as issues. So is "I tried to build this and it didn't
work" — that's a documentation bug and we'd like to know.
