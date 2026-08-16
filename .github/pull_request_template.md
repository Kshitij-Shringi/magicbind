<!--
Thanks for contributing.

Target `develop`, not `main`. See CONTRIBUTING.md for branch naming and commit
conventions.
-->

## What this does

<!-- A short description. If it's obvious from the title, one line is fine. -->

## Why

<!--
The motivation, or the issue it closes. If it's a bug fix, what was the root
cause?
-->

Closes #

## Type of change

- [ ] `feat` — new capability
- [ ] `fix` — bug fix
- [ ] `docs` — documentation only
- [ ] `test` — tests only
- [ ] `refactor` — no behavior change
- [ ] `perf` — performance
- [ ] `build` / `ci` / `chore` — tooling and housekeeping
- [ ] Breaking change (config format or public API)

## How it was tested

<!--
Automated coverage first, then manual. If you changed GestureRecognizer or
ConfigStore, tests are expected — see CONTRIBUTING.md.
-->

**Automated:**

**Manual** (which device, which macOS version, which gestures you actually
tried):

## Checklist

- [ ] Branched from `develop` and targeting `develop`
- [ ] `swift build` succeeds
- [ ] `swift test` passes
- [ ] `swiftlint --strict` is clean
- [ ] Commits follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
- [ ] `CHANGELOG.md` updated under `## [Unreleased]` (skip for pure
      refactors, tests, or internal docs)
- [ ] Docs updated if behavior changed
- [ ] No new dependencies (or the PR explains why one is worth it)

## If you touched the sensitive files

<!-- Delete this whole section if none of it applies. -->

- [ ] **`GestureRecognizer` thresholds** — I measured this on real hardware and
      the PR says which device, macOS version, and gesture. (Numbers in that
      file need a story.)
- [ ] **`MultitouchTypes` struct layout** — I verified against real frames, and
      described what I observed.
- [ ] **`ActionExecutor`** — this still only *posts* events and never installs a
      tap to observe input.
- [ ] **Anything touching the network** — I've read SECURITY.md; "nothing leaves
      the device" is a hard guarantee, and this PR does not break it.

## Screenshots or recording

<!-- For UI changes. A short screen recording of a gesture firing is ideal. -->

## Notes for the reviewer

<!--
Anything you're unsure about, tradeoffs you made, or parts you'd like a closer
look at. Flagging your own doubts speeds up review.
-->
