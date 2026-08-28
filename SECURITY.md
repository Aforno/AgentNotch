# Security policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do
not include vulnerability details, proof-of-concept code, credentials, or
private data in a public issue. If private reporting is temporarily
unavailable, contact the maintainer through GitHub with only a request to
establish a private channel.

Include the affected version, realistic attack path, security impact, required
attacker capabilities, and the smallest safe reproduction. Please use
synthetic data and avoid accessing another person's files or sessions.

## Supported versions

Security fixes are made on the latest release and `main`. Older pre-1.0 builds
may be asked to upgrade before a report is investigated.

## System and scope

Agent Notch is a local macOS app. In scope are the SwiftUI/AppKit app, the
`AgentsNotchCore` protocol and reducer, the bundled hook relay, provider
configuration installation and removal, local persistence, release scripts,
and GitHub Actions workflows.

The app is not an internet service. It receives newline-delimited JSON from
local provider hooks over a Unix-domain socket and displays local agent status.
It modifies only its own entries in supported provider hook configuration.

## Threat model and trust boundaries

- Hook payload text, paths, URLs, tool input, and metadata are untrusted input,
  even when delivered by a supported provider.
- Processes running as the same macOS user are trusted to connect to the local
  socket; other users must not be able to read from or write to it.
- Existing provider configuration and plugins belong to the user and must be
  preserved across install, refresh, and removal.
- Provider hooks are observers unless the user enables Answer from the notch.
  When enabled, the app starts `~/.agentnotch/reply.sock` with mode `0600` and
  accepts grant or deny decisions for waiting tools. Same-user processes can
  connect. The app never grants automatically, and Privacy mode disables all
  answers. If no answer arrives within 120 seconds, the provider shows its own
  prompt.
- Release artifacts cross a separate trust boundary and must match reviewed
  source, version metadata, Developer ID signing, and Apple notarization.

## Security invariants

- The default socket directory is mode `0700`, the socket is mode `0600`, and
  an individual payload is bounded to 1 MiB.
- The relay returns success and an empty passive response when the app is
  unavailable, an event is malformed, or an Answer from the notch wait times
  out.
- The app does not invent a transcript parser, inject agent context, upload
  source, or send analytics or telemetry. The one Codex exception is a
  fail-open 4 MiB tail read used only to decide whether a PermissionRequest
  is waiting on a person; missing context stays visible.
- Update checks fetch only the GitHub Releases Sparkle appcast. The ZIP is
  downloaded after the user chooses Download. Sparkle verifies the EdDSA
  signature against the baked-in public key and the Developer ID signature
  before replacing the running app. System profile data is not sent.
- Integration changes are atomic and idempotent, preserve unrelated settings,
  preserve restrictive file permissions and symlinked dotfiles, and remove
  only Agent Notch entries.
- Untrusted event content is rendered as data. It must not become shell input,
  hook configuration, executable code, or automatic navigation.
- Published binaries are release builds with debug-only UI removed, signed
  inside-out with hardened runtime, notarized, stapled, and checksummed.
- Credentials and signing material must never enter source, artifacts, or logs.

## Reportable findings and severity context

Report unauthorized cross-user socket access, code execution or configuration
injection, destructive modification of unrelated provider settings, automatic
execution or navigation caused by event data, transcript/source/credential
disclosure, undeclared networking, release-workflow credential exposure, or a
way to substitute an unreviewed published artifact.

Remote or cross-user compromise, arbitrary code execution, credential theft,
and release supply-chain compromise are high-impact. Same-user denial of
service or forged display-only activity is generally lower severity unless it
crosses another boundary or enables additional impact.

## Out of scope and accepted limitations

- Cosmetic UI defects and provider lifecycle mismatches without a security
  impact.
- A process already running as the same macOS user sending forged display-only
  events, without privilege escalation, code execution, sensitive disclosure,
  or persistent configuration impact.
- Availability failures caused solely by a provider changing an undocumented
  payload.
- Ad-hoc signatures produced by the explicitly local `--adhoc` packaging mode;
  those artifacts are never intended for distribution.

The app is not sandboxed and relies on macOS account isolation and private Unix
socket permissions. Supported provider hook schemas can evolve, so mappings
and configuration paths must be revalidated when integrations change.
