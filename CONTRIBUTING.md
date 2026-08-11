# Contributing to Agents Notch

Thank you for helping improve Agents Notch. Bug reports, focused fixes,
documentation improvements, and new provider adapters are welcome.

## Development setup

Requirements:

- Apple Silicon Mac running macOS 14 or later
- Swift 6
- Git

Clone the repository and run the full local checks:

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

- Keep pull requests focused and explain the user-visible behavior they change.
- Add regression tests for reducer, protocol, socket, persistence, or integration
  configuration behavior.
- Provider integration changes must preserve unrelated user configuration,
  remain idempotent, and never turn the observer hook into a policy decision.
- Do not commit build output, release archives, credentials, local agent data, or
  scraped web caches.
- Update `CHANGELOG.md` for user-visible changes.

## Pull requests

Before opening a pull request, run the commands above and include:

- a concise description of the problem and solution;
- tests performed, including packaged-app verification when UI or runtime code
  changes;
- screenshots for meaningful UI changes;
- any compatibility implications for supported provider hooks or plugins.

By contributing, you agree that your contribution is licensed under the
project's license.

Security vulnerabilities should be reported privately as described in
`SECURITY.md`, not through a public issue.
