# Development

Build requirements and launch instructions: [README](../README.md).

## Tests

```sh
./scripts/test.sh
./scripts/test.sh --filter PocketTests
./scripts/test.sh --filter PocketAnimationTests --no-parallel
```

Normal tests stay offscreen. Optional desktop checks **open windows and change focus**:

```sh
POCKET_DESKTOP_TESTS=1 ./scripts/test.sh --filter 'PanelLifecycleTests|SettingsLifecycleTests' --no-parallel
```

Test observable behavior through its owning interface. Keep clock-driven animation tests separate from fast unit tests.

## Ownership

- AppKit owns windows; SwiftUI composes presentation; native text views own editing.
- Conversation and reply work outlive the panel. Hiding UI must never cancel work.
- Inject backends at app composition; keep transport details inside adapters. The current backend only simulates replies.

## Manual checks

- Open, close, type, and interrupt animations; preserve drafts, selection, undo, and scroll position.
- Check cross-app focus restoration, shortcut conflicts, and launch at login.
- Try notched/external displays, display switching, fullscreen, and Spaces.
- Check Reduce Motion mid-animation, Increase Contrast, and Reduce Transparency.
- Replies continue while hidden; unread markers clear only after viewing the completed reply to its end.

## Menu-bar artwork

Regenerate icons, then rebuild:

```sh
swift scripts/generate-menu-icons.swift
./scripts/build-app.sh
```

[Design and motion](design.md)
