# Testing MagicBind

Thanks for trying this. MagicBind is pre-1.0 and the gesture recognizer has
**never been calibrated against real hardware** — the thresholds are educated
guesses. Misfires are expected, and telling us about them is the single most
useful thing you can do.

Read [what to actually test](#what-to-actually-test) before you start, so your
time goes somewhere useful.

## Before you install: two things you should know

**1. MagicBind needs Accessibility permission.** It has to, in order to post the
clicks and keystrokes your gestures are bound to. That is a broad permission —
be as skeptical of this app as you'd be of any other that asks for it. The whole
thing is MIT-licensed and small; [SECURITY.md](../SECURITY.md) explains exactly
what it does and doesn't touch, and the file that posts events is about 200
lines.

**2. Test builds are not signed by Apple.** There's no Apple Developer Program
membership behind this yet, so builds are *ad-hoc signed*. macOS will refuse to
open a downloaded copy until you explicitly override it. That override is a real
security decision, not a formality — which is why **building from source is the
recommended path** and gets its own section first.

## Option A — build it yourself (recommended)

Nothing to override, because locally-built apps aren't quarantined. Takes about
a minute.

**Requirements:** macOS 13+, and Xcode or Command Line Tools
(`xcode-select --install`).

```sh
git clone https://github.com/Kshitij-Shringi/magicbind.git
cd magicbind
./Scripts/build_app.sh
open build/MagicBind.app
```

Grant Accessibility when prompted (System Settings → Privacy & Security →
Accessibility), then **quit and relaunch** — macOS doesn't extend the permission
to an already-running process.

> [!TIP]
> After a rebuild, gestures sometimes stop firing silently. Ad-hoc signatures
> change on every build, so macOS can treat the rebuilt app as a different one
> and quietly stop honoring the permission. Remove MagicBind from the
> Accessibility list and re-add it.

## Option B — a zip someone sent you

```sh
# 1. Verify it's what the sender built
shasum -a 256 MagicBind-0.2.0-dev.zip
#    compare against the .sha256 file they sent alongside it

# 2. Unpack and install
unzip MagicBind-0.2.0-dev.zip
mv MagicBind.app /Applications/

# 3. Clear the download quarantine flag
xattr -dr com.apple.quarantine /Applications/MagicBind.app

# 4. Launch
open /Applications/MagicBind.app
```

Step 3 is what stops macOS from refusing to open it. If you skip it and get
*"Apple could not verify MagicBind is free of malware"*, either run step 3 and
try again, or go to **System Settings → Privacy & Security**, scroll to the
blocked-app notice, and click **Open Anyway**.

> [!WARNING]
> On macOS 15 and later, right-click → Open no longer bypasses this for
> unsigned apps. Use the `xattr` command or the System Settings override.

Only do this for a build from someone you actually trust. You are granting
Accessibility to an app whose provenance macOS could not verify.

## Using it

MagicBind lives in the menu bar with no Dock icon. Choose **Open MagicBind…**
from the menu bar icon to get the window.

Defaults out of the box:

| Gesture | Action |
|---|---|
| 3-finger tap | Middle click |
| 4-finger tap | Screenshot region (⌘⇧4) |

The window has three screens, via the icons at the top:

- **Device** — every non-swipe binding as a chip around the mouse. Click a chip,
  then pick an action from the panel on the right.
- **Custom gestures** — swipes laid out by direction, one finger count at a
  time. Click an "Unassigned" direction to bind it.
- **Settings** — recognizer thresholds, and the mouse-button opt-in.

**Click gestures are off until you turn them on.** Settings → *Watch physical
mouse buttons*. That installs a listen-only event tap;
[SECURITY.md](../SECURITY.md#risk-disclosure-mouse-button-watching) explains
what it can and can't see. Taps, double taps, holds, and swipes need none of it.

## What to actually test

Roughly in order of how much we'd learn:

**1. Does the touch data work at all on your Mac?** This is the big unknown. The
`MTFinger` memory layout is reverse-engineered from a private Apple framework
and is unverified across macOS versions and hardware.

Open the window and rest fingers on the mouse. Watch the **"Last: …"** readout in
the bottom-right corner.

| What you see | What it means |
|---|---|
| Nothing, ever | The reader or the struct layout is wrong on your machine. **Most valuable bug report there is** — include your exact macOS version and Mac model. |
| The wrong gesture | Threshold problem. Say which gesture you made and which appeared. |
| The right gesture, but nothing happens | Permission or action problem, not recognition. |

**2. False triggers during normal use.** Browse and work normally for ten
minutes with the defaults on. Does anything fire that you didn't intend? Resting
a third finger on the mouse while scrolling is the classic culprit.

**3. Gestures that don't fire when you mean them.** The opposite failure. Which
gesture, how hard/fast did you do it?

**4. Shortcut recording.** Settings aside, this is the newest code. In the
Actions panel pick **Keyboard Shortcut**, click the field, and try:

- a plain combination like ⌥⌘K
- **⌘W and ⌘Q** — these are key equivalents the menu bar wants to eat, and were
  broken until recently. They should record, not close the window or quit.
- **Escape** should cancel, **Delete** should clear
- a function key, an arrow key, ⌘⌫

**5. Double tap.** Note the deliberate behavior: a double tap fires **`Tap`
first, then `Double Tap`**. Suppressing the leading tap would mean delaying
*every* tap, making single taps feel laggy. So bind one or the other, not both.
Tell us if this feels wrong in practice.

**6. Non-English keyboard layouts.** Shortcut labels are resolved against your
current layout, not a US table. If you're on AZERTY, Dvorak, or anything
non-QWERTY, do the glyphs match the keys you actually pressed?

**7. Intel Macs.** Universal builds are new and untested on x86_64. If you're on
an Intel Mac, "it launched" is itself a useful report.

## Reporting

File an issue: https://github.com/Kshitij-Shringi/magicbind/issues — the bug
template asks for what's needed. Please include:

- **The version and build.** In the app: menu bar → Open MagicBind… → Settings,
  at the bottom. Or:
  ```sh
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    /Applications/MagicBind.app/Contents/Info.plist
  /usr/libexec/PlistBuddy -c "Print :MagicBindGitSHA" \
    /Applications/MagicBind.app/Contents/Info.plist
  ```
- **macOS version and Mac model** — `sw_vers` and Apple menu → About This Mac.
- **Which device** — Magic Mouse, Magic Mouse 2, Magic Trackpad?
- **What the "Last: …" readout showed** when the problem happened. This is the
  single most diagnostic detail; see the table above.
- **Your bindings**, if relevant. Settings → Reveal in Finder, or:
  ```sh
  cat ~/Library/"Application Support"/MagicBind/config.json
  ```
  It contains only your gesture bindings and thresholds — no personal data.

Anything in Console.app filtered to `MagicBind` is a bonus.

Found a *security* problem? Don't file a public issue — see
[SECURITY.md](../SECURITY.md#reporting-a-vulnerability).

## Uninstalling

```sh
rm -rf /Applications/MagicBind.app
rm -rf ~/Library/"Application Support"/MagicBind
```

Then remove MagicBind from System Settings → Privacy & Security →
Accessibility. Nothing else is left behind — no launch agents, no preferences
outside that folder, no receipts.

## For the maintainer: cutting a test build

```sh
./Scripts/package_release.sh
```

Builds universal, stamps the version from `VERSION` plus the git SHA, packages a
zip with `ditto` (so the signature survives), and writes a checksum. It prints a
`gh release create --prerelease` command to publish it.

The friction in Option B goes away entirely with an Apple Developer Program
membership: sign with a Developer ID, run `xcrun notarytool submit --wait`, then
`xcrun stapler staple`, and testers just double-click. That's
[Phase 7](../ProjectPlan.md).
