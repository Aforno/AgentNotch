# Releasing Agent Notch

Production releases are Apple Silicon ZIP archives. They are signed with a
Developer ID Application certificate, notarized by Apple, stapled, and shipped
with a SHA-256 checksum. Unsigned prereleases are ad-hoc signed and labeled as
previews. Never present them as notarized builds.

## Prepare the release

1. Move the relevant `CHANGELOG.md` entries from `Unreleased` into a versioned
   section.
2. Update `VERSION` using semantic versioning.
3. Run:

   ```sh
   swift test
   swift test -c release
   ./script/package_release.sh --adhoc
   ./script/check_repository.sh
   ```

4. Commit those changes and create a signed tag matching `v$(cat VERSION)`.

## Local signed and notarized package

Store App Store Connect credentials in a notarytool keychain profile once:

```sh
xcrun notarytool store-credentials agent-notch-notary
```

Then package with the exact Developer ID identity shown by
`security find-identity -p codesigning -v`:

```sh
AGENT_NOTCH_BUILD_NUMBER=1 ./script/package_release.sh \
  --identity "Developer ID Application: Example Name (TEAMID)" \
  --notarize \
  --keychain-profile agent-notch-notary
```

The script builds the release configuration for arm64, signs nested code
(including Sparkle) and the app with hardened runtime, verifies the bundle,
notarizes and staples it, re-verifies Gatekeeper acceptance, and writes the ZIP
plus `.sha256` file under `dist/`.

Signed releases also publish a Sparkle `appcast.xml`. Generate it from the ZIP
with the EdDSA private key that matches `Resources/SparklePublicEDKey`:

```sh
SPARKLE_ED_PRIVATE_KEY="$(cat /path/to/sparkle-ed-private-key)" \
  ./script/generate_appcast.sh
```

The private key is the 32-byte EdDSA seed, base64-encoded. Never commit it. The
appcast enclosure URL is the GitHub release asset for that ZIP. In-app updates
read `https://github.com/Aforno/AgentNotch/releases/latest/download/appcast.xml`.

## GitHub release workflow

Both `Release` and `Nightly` set `AGENT_NOTCH_BUILD_NUMBER` to Unix time in
seconds when packaging starts. This becomes `CFBundleVersion`, replacing the
independent `GITHUB_RUN_NUMBER` counters. Sparkle compares this value, so both
workflows use the same time-based ordering. Nightly apps still check the stable
appcast and can update to a stable build packaged later.

The `Release` workflow requires these repository Actions secrets:

- `MACOS_CERTIFICATE`: base64-encoded Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD`: password for that `.p12`
- `MACOS_SIGNING_IDENTITY`: full Developer ID Application identity
- `APPLE_API_KEY_ID`: App Store Connect API key ID
- `APPLE_API_ISSUER_ID`: App Store Connect issuer ID
- `APPLE_API_PRIVATE_KEY`: complete `.p8` private-key contents
- `SPARKLE_ED_PRIVATE_KEY`: base64 EdDSA seed that matches
  `Resources/SparklePublicEDKey`

Push a signed `vX.Y.Z` tag only after CI passes. All tags share one `release`
concurrency group, so one GitHub release runs at a time. The workflow validates
that the tag matches `VERSION`, imports the temporary certificate, builds and
notarizes the app, creates the checksum, signs a Sparkle appcast, and publishes
the ZIP, checksum, and `appcast.xml` to the GitHub release. After the GitHub
files are up, it points `Casks/agent-notch.rb` at that ZIP and checksum and
pushes the cask bump to the default branch unless the cask already names a
newer version. Homebrew users on this tap pick that up with `brew update`.
Packaged apps check the appcast on launch and once a day, then wait for the
user to download and restart. The cask sets `auto_updates true` so Homebrew
does not fight the in-app updater.

If the cask commit cannot push, update it locally from the published checksum:

```sh
./script/update_cask.sh --version "$(tr -d '[:space:]' < VERSION)" \
  --checksum-file "dist/Agent-Notch-$(tr -d '[:space:]' < VERSION)-macOS-arm64.zip.sha256"
```

Do not rewrite the cask SHA-256 during release prep. The checksum belongs to the
notarized GitHub artifact, not a local ad-hoc rebuild.

Signing credentials are an external release gate. Never commit them to this
repository or print them in workflow logs.

## Unsigned prerelease

When signing credentials are unavailable and an unsigned preview is explicitly
approved, opt in before pushing the tag:

```sh
gh variable set RELEASE_MODE --repo Aforno/AgentNotch \
  --body unsigned-prerelease
git tag -a "v$(cat VERSION)" -m "Agent Notch $(cat VERSION)"
git push origin "v$(cat VERSION)"
```

The workflow ad-hoc signs the app, marks the GitHub release as a prerelease,
and puts a notarization and Gatekeeper warning at the top of its notes. After
the release succeeds, remove the temporary opt-in so later tags default back to
the signed release path:

```sh
gh variable delete RELEASE_MODE --repo Aforno/AgentNotch
```

## Nightly builds

Automated nightly builds run via `.github/workflows/nightly.yml`:

- Runs daily at 02:00 UTC and skips when `HEAD` matches `nightly-published`,
  the commit marker written after release publishing and asset cleanup succeed.
  Failed publishing is retried on the next scheduled run regardless of commit age.
- Can also run manually via `workflow_dispatch`; `force` defaults to `true`
  to rebuild an already published commit. Set it to `false` to use the same skip
  check as scheduled runs.
- Packaging creates a versioned ZIP in `dist/` and copies it to
  `Agent-Notch-Nightly-macOS-arm64.zip`. Only the fixed Nightly ZIP and its
  `.sha256` checksum are published to the rolling `nightly` GitHub prerelease
  and retained in the Actions artifact for 7 days. Obsolete versioned release
  assets are removed.
- Signs and notarizes if Developer ID credentials are configured in repository
  secrets; falls back to an ad-hoc signed preview if secrets are unavailable or
  if opted out via `NIGHTLY_RELEASE_MODE=unsigned` or
  `RELEASE_MODE=unsigned-prerelease`.
- Does not modify `Casks/agent-notch.rb` or publish a Sparkle appcast.
