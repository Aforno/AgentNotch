# UI guidelines

Shared look lives in `NotchWindowStyle.swift`: opaque near-black surfaces,
hairline separators, raised fills, a white-opacity text ladder, small 8-10
point radii, and state colors from `agentStateColor(for:)`. Do not use
`.black` font weights. Settings, Activity Center, and onboarding share that
look. Settings rows are title plus detail, switch toggles, and compact dark
pills.

Every clickable surface answers the pointer. Styles route their rest, hover,
and press fills through `NotchHoverSurface`; deep-black window controls take
theirs from `NotchControlFill` and draw with `notchControlSurface(fill:)`.
Floating panels cannot blend into black, so they use the opaque `floating`
palette entries instead of the white-opacity ladder. A disabled row dims once,
at the row, one rung down the text ladder.

Surfaces that hide their scroll indicators mark content with
`notchScrollContent()` and the scroll view with `notchScrollEdgeFade()`, so a
faded edge is the cue that more remains. A surface whose height is capped must
scroll: no control may be clipped out of reach.

## Notch presentation

- Stay collapsed for routine tool, edit, and completion activity.
- Expand automatically only for permission or answer attention.
- When answering is enabled and a waiting session has `pendingReply`, show its
  prompt and available actions before the session list. Privacy mode hides the
  prompt and disables its actions.
- Show the three most recently updated agent groups in the expanded list.
- Queue multiple waiting sessions and show waiting or failed descendants on
  their parent row.
- Command-1, the notch chrome, or the global activity shortcut opens Activity
  Center.
- A clicked thread stays pinned until Back or a click outside the notch.
- Thread detail offers Open in Codex/Open session/Open app and Open terminal as
  separate actions when both origins exist. Reveal repository appears only
  when no app, session, or terminal destination exists for a non-Codex
  provider. Internal Codex helpers do not expose an origin action.

UI behavior and layout changes need `./script/build_and_run.sh --verify` plus
visual inspection of the packaged app at native scale. Socket and process
health alone do not prove layout. Include screenshots in a pull request when
layout changes.
