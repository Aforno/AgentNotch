# Contributing to Agents Notch

Bug reports, focused fixes, documentation, and new provider adapters are
welcome.

## Development setup

Requirements:

- Apple Silicon Mac running macOS 14 or later
- Swift 6 toolchain (package language mode is Swift 6)
- Git

Clone the repository and run the local checks:

```sh
swift test
swift test -c release
./script/package_release.sh --adhoc
./script/check_repository.sh
```

To launch a development build:

```sh
./script/build_and_run.sh --verify
```

## Making changes

- Keep pull requests focused. Say what the user will see change.
- Add regression tests for reducer, protocol, socket, persistence, or
  integration configuration behavior.
- Provider integration changes must preserve unrelated user configuration,
  stay idempotent, and never turn the observer hook into a policy decision.
- Do not commit build output, release archives, credentials, local agent data,
  or scraped web caches.
- Update `CHANGELOG.md` for user-visible changes.

## Pull requests

Before opening a pull request, run the commands above and include:

- a short description of the problem and the fix;
- tests you ran, including packaged-app verification when UI or runtime code
  changes;
- screenshots for meaningful UI changes;
- any compatibility implications for supported provider hooks or plugins.

Contributions are licensed under the project's license.

Report security vulnerabilities privately as described in `SECURITY.md`, not in
a public issue.
