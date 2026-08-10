# Security Policy

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately using either:

1. **GitHub private vulnerability reporting** — go to the
   [Security tab](https://github.com/Kshitij-Shringi/magicbind/security/advisories/new)
   and open a draft advisory. This is the preferred route; it keeps the
   discussion attached to the repository.
2. **Email** — <kshitij.shringi@pedalsup.com>, with `MagicBind security` in the
   subject line.

Please include:

- what you observed, and what you expected instead
- the macOS version and hardware (Magic Mouse, Magic Trackpad, Mac model)
- the MagicBind version or commit SHA
- steps to reproduce, and a proof of concept if you have one

**What to expect:** an acknowledgement within 7 days, an assessment within 30
days, and credit in the release notes when a fix ships — unless you'd rather
stay anonymous, which is fine. Please give us a reasonable window to ship a fix
before disclosing publicly.

## Supported versions

MagicBind is pre-1.0. Only the latest release on the default branch receives
security fixes. There are no backports to older tags.

## What MagicBind does with your data

Nothing leaves your device. Concretely:

- **No telemetry, no analytics, no crash reporting.** There is no server, no
  API key, and no account. The app makes no network requests of its own.
- **No touch or keystroke logging.** Touch frames are classified in memory and
  discarded. Nothing is written to disk, and MagicBind does not read the
  contents of your keystrokes or the windows of other apps.
- **The only file written** is your configuration, at
  `~/Library/Application Support/MagicBind/config.json`. It is plain,
  hand-editable JSON containing your gesture bindings and recognizer
  thresholds. Nothing else.
- **Mouse button watching is opt-in and narrow.** If you enable Click gestures,
  MagicBind observes mouse button events — see
  [the next section](#risk-disclosure-mouse-button-watching) for exactly what
  that does and doesn't read. It is off by default.

If you configure a `shellCommand` or `appleScript` action, *that command* can
of course do anything you tell it to, including reaching the network. That is
your script, running as you, at your request — but be aware that a
gesture-triggered script is code you may not remember writing six months later.
Treat config files shared by other people the same way you'd treat any script
someone sent you.

## Risk disclosure: private Apple frameworks

This is the part you should read before installing.

MagicBind reads Magic Mouse and Magic Trackpad touch data through
**`MultitouchSupport.framework`, a private, undocumented Apple framework**.
There is no public API for multi-finger touch data on these devices, so every
project in this space — including
[MiddleClick](https://github.com/artginzburg/MiddleClick) and
[BetterTouchTool](https://folivora.ai) — depends on the same private
framework. It is the only way this category of app can exist.

What that means in practice:

- **It can break without warning.** Apple can change, rename, or remove these
  symbols in any macOS update, including a point release. Historically this has
  broken every project in this space at least once. MagicBind resolves the
  framework at runtime with `dlopen`/`dlsym` rather than linking against it, so
  a missing symbol degrades to "gestures stop working" with a surfaced error
  rather than a crash on launch — but it will still stop working.
- **The struct layout is reverse-engineered.** `MTFinger` in
  [MultitouchTypes.swift](Sources/MagicBindCore/MultitouchTypes.swift) mirrors
  the commonly documented shape of Apple's internal struct. If Apple changes
  that layout, MagicBind will read misaligned memory and produce garbage
  coordinates. This is a correctness and stability risk, not a remote-attack
  risk — the data comes from your own hardware — but it is why the reader is
  isolated behind one small, auditable file.
- **This is not a supported configuration.** Apple does not document, test, or
  guarantee any of it. Do not deploy MagicBind on a machine where an
  unexpected input-handling failure would be costly.

## Risk disclosure: Accessibility permission

MagicBind requires **Accessibility** permission (System Settings → Privacy &
Security → Accessibility) because posting a synthetic middle click or keystroke
via `CGEvent` is privileged.

Be clear-eyed about what you are granting: Accessibility is a broad permission.
An app that holds it *could* observe and synthesize input across your entire
system. MagicBind synthesizes only the events your bindings ask for, in
[ActionExecutor.swift](Sources/MagicBindCore/ActionExecutor.swift) — the only
file that posts a `CGEvent`. But "trust me" is not a security model, which is
why the whole thing is MIT-licensed and small enough to read.

> [!IMPORTANT]
> **This section changed in 0.2.0.** Earlier versions of this document promised
> that MagicBind "never installs an event tap to observe your input". That is no
> longer unconditionally true: enabling Click gestures installs a listen-only
> tap on mouse button events. The section below describes exactly what it reads.
> The guarantee that *nothing leaves your device* is unchanged.

## Risk disclosure: mouse button watching

Click gestures — "2-finger click", "middle button click" — need to know that you
pressed a physical button. **Touch frames from the multitouch framework do not
contain button state**, so there is no way to recognize a click without
observing button events. That means an event tap.

**It is off by default.** Turn it on in Settings → "Watch physical mouse
buttons", or leave it off and use taps, holds, and swipes, which need no tap at
all.

What the tap does, in
[MouseButtonMonitor.swift](Sources/MagicBindCore/MouseButtonMonitor.swift):

- It is created with **`.listenOnly`**, so it *cannot* modify, suppress, or
  inject events. Every click passes through to the app you clicked, unchanged.
  MagicBind cannot swallow your clicks even by accident.
- Its event mask covers **only** the six mouse button events (left/right/other,
  down and up). Key events, scroll events, and mouse movement are not in the
  mask and are never delivered to MagicBind.
- From each event it reads **one field**: the button number. It does not read
  the cursor location, the timestamp, the modifier flags, the click count, or
  the target window.
- Nothing is logged, buffered, or written to disk. The button number is turned
  into a `GestureSpec`, matched against your bindings, and discarded.

What you are nonetheless trusting: a listen-only tap still means the process
receives a callback on every mouse button press system-wide, including presses
inside your password manager or banking site. MagicBind ignores everything but
the button number — but that is a property of the source code, not of the
sandbox. If that tradeoff isn't worth Click gestures to you, leave the setting
off. That's why it's a setting.

For comparison: Logi Options+, BetterTouchTool, and Mac Mouse Fix all watch
input this way, and most of them are closed source. This one you can read.

## Not sandboxed, and why

MagicBind cannot be sandboxed. The App Sandbox blocks both loading the private
framework and posting `CGEvent`s, which is the entire app. Consequences:

- It cannot ship on the Mac App Store.
- Distribution is by direct download or Homebrew cask.
- **Prefer builds you compiled yourself, or signed and notarized releases from
  this repository.** An unsigned build of an app that asks for Accessibility,
  handed to you by a third party, is exactly the shape of a credible attack.
  Check the release signature, or build from source — it's one `swift build`.
