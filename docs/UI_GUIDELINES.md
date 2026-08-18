# UI Guidelines

Shared chrome lives in `NotchWindowStyle.swift`: opaque near-black surfaces,
hairline separators, raised fills, a white-opacity text ladder, small 8-10 point
radii, and state colors from `agentStateColor(for:)`. Avoid `.black` font weights.
Settings, Activity Center, and onboarding use the same vocabulary. Settings rows
are title plus detail, switch toggles, and compact dark pills.

## Notch presentation

- Stay collapsed for routine tool, edit, and completion activity.
- Expand automatically only for permission or answer attention.
- Show the three most recently updated agent groups in the expanded list.
- Queue multiple waiting sessions and surface waiting or failed descendants on
  their parent row.
- Command-1, the notch chrome, or the global activity shortcut opens Activity
  Center.
- A clicked thread stays pinned until Back or a click outside the notch.

UI behavior and layout changes require `./script/build_and_run.sh --verify` plus
visual inspection of the packaged app at native scale. Socket and process health
alone do not prove layout. Include screenshots in a pull request when layout
changes.
