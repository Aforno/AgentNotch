# Agent Notch beta testing

Agent Notch is a pre-1.0 beta for Apple Silicon Macs running macOS 14 or later.
Unsigned previews are not notarized by Apple and update manually.

## Install

Follow the [unsigned beta installation instructions](../README.md#unsigned-beta).
Use the ZIP and checksum from the same release. Keep the release URL: nightly
builds can share a version number, so the date and commit in the release notes
identify the build you tested.

## Try it for 10–15 minutes

1. Open the app and connect a provider you already use in Setup. Follow any
   trust instructions. Agent Notch should preserve your other provider hooks.
2. Start a normal coding task. Hover over the notch to see activity, then open
   Activity Center. Check that the session, repository, and current state make
   sense. Routine work should leave the notch collapsed when you move away.
3. If your provider asks for permission or an answer, check that the notch
   draws your attention. Cursor cannot report its native approval dialog.
   Optionally enable **Settings → Alerts & Privacy → Answer from the notch**
   for Codex or Claude Code and try a prompt whose actions appear in the notch.
   The provider's own prompt remains the fallback if no answer arrives.
4. Finish the task. Check that the session stops spinning and its completed
   state appears in Activity Center. Try the session's open action.
5. Quit using **Settings → General → Quit Agent Notch**, then reopen the app.
   Check that history remains and new tasks still report activity.
6. Open **Settings → General → View Downloads**. For an unsigned beta, this
   should open the release downloads page; updates are installed by quitting
   and replacing the app in Applications. Check history after a manual update
   when another build becomes available.
7. When finished testing, remove the observer in **Settings → Integrations**.
   Other hooks should remain. Run another task in the provider to check that
   it still works normally. You can reinstall the observer to keep using it.

If you use an external monitor or a Mac without a physical notch, also try
the display preference and virtual notch in Settings → General.

## Send feedback

Use the [bug report form](https://github.com/Aforno/AgentNotch/issues/new?template=bug_report.yml).
Include the release URL (or nightly date and commit), macOS version, Mac model,
provider and its version, what you did, what you expected, and what happened.
For a visual problem, a cropped screenshot helps; remove private task text.
Report installation and Gatekeeper problems too.

## Maintainer handoff

Start with 3–5 testers using their own Macs. Include someone doing a fresh
install, someone using a different provider, and an external-display user if
available. Send the same release URL and this guide to everyone.

Build a local unsigned preview with:

```sh
swift test -c release
./script/check_repository.sh
./script/package_release.sh --adhoc
```

Share the ZIP and matching `.sha256` from `dist/`, labeled **Unsigned Beta —
not notarized by Apple**, with the source commit. For GitHub downloads, use
the existing Nightly workflow or the explicitly opted-in
[unsigned prerelease workflow](RELEASING.md#unsigned-prerelease). Neither
requires Apple signing credentials. Unsigned prereleases leave the Homebrew
cask unchanged.

Fix repeatable installation, missed-attention, stale-session, and removal
problems before expanding the feature set.
