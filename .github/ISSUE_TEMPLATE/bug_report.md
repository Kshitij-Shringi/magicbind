---
name: Bug report
about: Something doesn't work the way it should
title: "fix: "
labels: bug
assignees: ''
---

<!--
Before filing, two quick checks that resolve most reports:

1. Is Accessibility permission granted, and did you RELAUNCH after granting it?
   System Settings > Privacy & Security > Accessibility. macOS does not extend
   the permission to an already-running process.
2. If you rebuilt the app, try removing MagicBind from the Accessibility list
   and re-adding it. Ad-hoc signatures change every build, so macOS may treat a
   rebuild as a different app.

Security issues: please do NOT file them here. See SECURITY.md for private
reporting.
-->

## What happened

<!-- What you observed. -->

## What you expected

<!-- What you expected instead. -->

## Steps to reproduce

1.
2.
3.

## Environment

| | |
|---|---|
| macOS version | <!-- e.g. 14.5 --> |
| Mac model | <!-- e.g. MacBook Pro M3, 2023 --> |
| Device | <!-- Magic Mouse / Magic Mouse 2 / Magic Trackpad 2 / other --> |
| MagicBind version or commit | <!-- e.g. v0.1.0 or a commit SHA --> |
| Built how | <!-- ./Scripts/build_app.sh / swift build / Xcode --> |
| Running from | <!-- MagicBind.app bundle / bare executable --> |

## Which gesture and binding

<!--
Which gesture, and what it's bound to. If it's easier, paste the relevant part
of ~/Library/Application Support/MagicBind/config.json — it contains no
personal data, just your bindings.
-->

## Diagnostics

- [ ] Accessibility permission is granted
- [ ] I relaunched MagicBind after granting it
- [ ] The menu bar shows the engine as running
- [ ] The preferences window's status row shows a "Last:" gesture when I touch
      the device

<!--
That last checkbox is the most useful signal in this whole template:

- No gesture shown at all -> the reader or the MTFinger struct layout is the
  problem (a private-framework issue, see SECURITY.md).
- The WRONG gesture shown -> a recognizer threshold problem; please say which
  gesture you made and which one appeared.
- The RIGHT gesture shown but nothing happens -> an action or permission
  problem.
-->

## Error message

<!-- Any error text from the preferences window, or from Console.app filtered to MagicBind. -->

```
paste here
```

## Anything else

<!-- Screenshots, a screen recording, or context you think matters. -->
