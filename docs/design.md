# Design

Pocket grows from the notch, not a separate floating card. The black silhouette
stays anchored to the top edge; content emerges beneath it.

## Presentation

- Opaque black housing, system typography, and an integrated native editor.
- No nested cards, window chrome, decorative controls, or hover affordances.
- Small clickable wings when closed; a compact top-edge tab on displays without a notch.
- Fit the composer around the buddy or one text line, then grow with the draft.
- Preserve draft, selection, undo, and reading position across collapse and reopen.
- Keep connection status honest and in the menu bar—not inside the composer.

## Motion

- Keep the top anchor fixed and transitions interruptible, preserving position and velocity.
- Animate the shell and content viewports together. Text never scales or blurs during content resizing.
- Accept typing immediately; reveal controls before allowing mouse interaction.
- Stop clocks at rest or when hidden. No polling, pulsing, or automatic expansion.
- Reduce Motion removes springs, scaling, movement, and blur; the buddy keeps only a subtle entrance fade.

## Conversation

- Capture comes first. Fresh openings show the composer, or the latest unread reply.
- Sending reveals history. Closing never cancels work or discards the conversation.
- Mark a completed reply read only when fully revealed, foreground, and viewed to its end.
- Distinguish turns through spacing and tone, without sender names or role headers.
- The local simulation must never imply a real connection, reasoning, or completed external action.

## Buddy

An optional, dithered companion beside the input. Brief entrance, occasional idle
blinks, and talking while replies stream; thinking stays still. Settings previews
react to customization, then return to rest. Hiding or Reduce Motion cancels animation.
Appearance changes must never interrupt editing or steal focus.

## References

- [Apple Design Resources](https://developer.apple.com/design/resources/)
- [Human Interface Guidelines: Motion](https://developer.apple.com/design/human-interface-guidelines/motion/)
- [Animate with springs](https://developer.apple.com/videos/play/wwdc2023/10158/)
- [SF Symbols](https://developer.apple.com/sf-symbols/)

Manual checks: [Development](development.md#manual-checks).
