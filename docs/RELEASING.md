# Releasing Agents Notch

Production Agents Notch releases are Apple Silicon ZIP archives signed with a
Developer ID Application certificate, notarized by Apple, stapled, and
accompanied by a SHA-256 checksum. Explicitly opted-in unsigned prereleases are
ad-hoc signed, clearly labeled as previews, and are never presented as
notarized builds.

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
xcrun notarytool store-credentials agents-notch-notary
```

Then package with the exact Developer ID identity shown by
`security find-identity -p codesigning -v`:

```sh
AGENTS_NOTCH_BUILD_NUMBER=1 ./script/package_release.sh \
  --identity "Developer ID Application: Example Name (TEAMID)" \
  --notarize \
  --keychain-profile agents-notch-notary
```

The script builds the release configuration for arm64, signs nested code and
the app with hardened runtime, verifies the bundle, notarizes and staples it,
re-verifies Gatekeeper acceptance, and writes the ZIP plus `.sha256` file under
`dist/`.

## GitHub release workflow

The `Release` workflow requires these repository Actions secrets:

- `MACOS_CERTIFICATE`: base64-encoded Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD`: password for that `.p12`
- `MACOS_SIGNING_IDENTITY`: full Developer ID Application identity
- `APPLE_API_KEY_ID`: App Store Connect API key ID
- `APPLE_API_ISSUER_ID`: App Store Connect issuer ID
- `APPLE_API_PRIVATE_KEY`: complete `.p8` private-key contents

Push a signed `vX.Y.Z` tag only after CI passes. The workflow validates that the
tag matches `VERSION`, imports the temporary certificate, builds and notarizes
the app, creates the checksum, and publishes both files to the GitHub release.

Signing credentials are an external release gate. They must never be committed
to this repository or printed in workflow logs.

## Unsigned prerelease

When signing credentials are unavailable and an unsigned preview is explicitly
approved, opt in before pushing the tag:

```sh
gh variable set RELEASE_MODE --repo Aforno/AgentNotch \
  --body unsigned-prerelease
git tag -a "v$(cat VERSION)" -m "Agents Notch $(cat VERSION)"
git push origin "v$(cat VERSION)"
```

The workflow ad-hoc signs the app, marks the GitHub release as a prerelease,
and puts a notarization and Gatekeeper warning at the top of its notes. After
the release succeeds, remove the temporary opt-in so later tags default back to
the signed release path:

```sh
gh variable delete RELEASE_MODE --repo Aforno/AgentNotch
```
