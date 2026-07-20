# Releasing LithePG

LithePG release artifacts are local-first macOS app bundles. Signing and notarization require Omar-controlled Apple Developer credentials; those credentials must stay in the local keychain or environment and must never be committed.

## Version policy

Stable releases use Semantic Versioning as `MAJOR.MINOR.PATCH`:

- Git tags add the conventional `v` prefix, for example `v1.0.0`.
- `CFBundleShortVersionString` contains only the numeric SemVer, for example `1.0.0`.
- `CFBundleVersion` remains a monotonically increasing numeric build identifier and defaults to the Git commit count.
- Increase `MAJOR` for incompatible changes, `MINOR` for backward-compatible features and `PATCH` for backward-compatible fixes.

Release scripts reject two-component or otherwise malformed stable versions.

## Local unsigned package verification

Build and verify the stripped app bundle:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package
./script/package_verify.sh dist/LithePG.app
```

For the final v1.0.0 candidate, do not rely on the current latest git tag to fill
`CFBundleShortVersionString`: the package builder derives that field from the
latest tag unless `LITHEPG_MARKETING_VERSION` is set. Build the candidate with
the intended marketing version, then verify the app bundle metadata with the
expected-version gate before any signing or notarization step:

```sh
LITHEPG_MARKETING_VERSION=1.0.0 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./script/build_and_run.sh --package

LITHEPG_EXPECTED_MARKETING_VERSION=1.0.0 \
./script/package_verify.sh dist/LithePG.app
```

If Omar chooses an explicit release build number for the candidate, set and
verify that number the same way:

```sh
LITHEPG_MARKETING_VERSION=1.0.0 \
LITHEPG_BUILD_VERSION=<build-number> \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./script/build_and_run.sh --package

LITHEPG_EXPECTED_MARKETING_VERSION=1.0.0 \
LITHEPG_EXPECTED_BUILD_VERSION=<build-number> \
./script/package_verify.sh dist/LithePG.app
```

The verifier checks:

- `Contents/MacOS/LithePGApp` exists and is executable.
- `Contents/Info.plist` has the expected executable, bundle identifier, bundle name, package type, numeric release/build version fields, minimum system version, and principal class.
- If `LITHEPG_EXPECTED_MARKETING_VERSION` or `LITHEPG_EXPECTED_BUILD_VERSION` is set, the corresponding bundle metadata exactly matches the expected value.
- The packaged executable stays below the 50 MiB hard cap.
- The executable contains no `/Users/<name>/...` build paths. Release packaging
  uses a fresh SwiftPM scratch directory under `/private/tmp` so dependency
  diagnostics cannot disclose the maintainer's home or project directory.

An unsigned/ad-hoc-signed local bundle is only a development artifact. Do not publish it as a public v1.0.0 release.

## Unnotarized Homebrew cask preview

When Apple Developer Program credentials are not yet available, a separate
preview helper can publish an explicitly ad-hoc-signed prerelease through the
project-owned Homebrew tap:

```sh
./script/release_cask_preview.sh
```

The helper prompts once for a stable base version such as `1.0.1` and publishes
`v1.0.1-preview.1`. Set `LITHEPG_CASK_PREVIEW_NUMBER` to a positive integer to
publish a later preview of the same base version. It runs the Swift tests,
forces and verifies ad-hoc signing, creates and verifies the GitHub prerelease
artifact, publishes a matching checksum sidecar, updates the managed release
block in `README.md`, and updates `omarpr/tap`. The external tap cask includes
a visible warning directing users to manually approve the first launch in
**System Settings → Privacy & Security**.

This preview path intentionally skips Developer ID signing, notarization, and
the official Homebrew new-cask audit. It cannot be submitted to
`homebrew/cask`, must never be described as Gatekeeper-trusted, and does not
replace the production `script/release.sh` workflow. Publish the eventual
notarized build under the stable tag rather than replacing preview bytes.

## Signed + notarized release path

`script/sign_and_notarize.sh` is the credential-gated wrapper for public macOS distribution. It expects a package produced by `script/build_and_run.sh --package` and reads configuration from environment variables only:

An Apple Developer Program membership is not required for local source builds or the ad-hoc development package, but the public release remains blocked without the Developer ID Application certificate and notarization access used by this section. Do not publish the local ad-hoc package as a substitute. When enrollment is available, start with Apple's [membership comparison](https://developer.apple.com/support/compare-memberships/), [Developer ID certificate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates) and [macOS notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) guidance, then return to the prepared commands below.

| Variable | Purpose |
| --- | --- |
| `LITHEPG_CODESIGN_IDENTITY` | Apple Developer Application signing identity for `codesign`. |
| `LITHEPG_NOTARY_PROFILE` | `xcrun notarytool` keychain profile name. |
| `LITHEPG_ENTITLEMENTS` | Optional entitlements override; defaults to `Sources/LithePGApp/LithePGApp.entitlements`. |
| `LITHEPG_NOTARY_ZIP` | Optional zip output path; defaults to `dist/LithePG-notary.zip`. |
| `LITHEPG_NOTARY_ZIP_OVERWRITE` | Optional explicit approval to replace an existing notary-submission zip; accepted values are `1`, `true`, `yes`, or `approved`. |

Check the configuration without signing or submitting anything:

```sh
LITHEPG_CODESIGN_IDENTITY="Developer ID Application: Omar Gerardo SF (LithePG)" \
LITHEPG_NOTARY_PROFILE="lithepg-notary" \
./script/sign_and_notarize.sh --dry-run dist/LithePG.app
```

Real signing/notarization runs:

1. `script/package_verify.sh` on the app bundle.
2. `codesign --deep --force --options runtime --timestamp` with the configured identity and entitlements.
3. `ditto` zip packaging for notary submission.
4. `xcrun notarytool submit --wait` using the configured keychain profile.
5. `xcrun stapler staple` and `xcrun stapler validate`.
6. `spctl --assess --type execute --verbose=4`.

If `LITHEPG_CODESIGN_IDENTITY` or `LITHEPG_NOTARY_PROFILE` is missing, the wrapper exits non-zero with a clear message. That is expected on machines without Apple Developer credentials.

The notary-submission zip is a credential-gated intermediate artifact, not the public release attachment. `script/sign_and_notarize.sh` refuses to use an existing `LITHEPG_NOTARY_ZIP` path, including a symlink at that path, unless `LITHEPG_NOTARY_ZIP_OVERWRITE` is explicitly approved (`1`, `true`, `yes`, or `approved`); the same guard runs during `--dry-run` so preflight catches stale zip artifacts before real signing/notary execution. After that approval gate passes, real mode may remove and recreate the zip as part of the signing/notarization flow; dry-run still creates no zip.

## GitHub Release artifact and Homebrew cask metadata

The historical v1.0 draft copy lives at [`docs/releases/v1.0-draft.md`](releases/v1.0-draft.md). Current stable release notes contain the versioned artifact, checksum and verification command, followed by GitHub's generated commit notes. The stable release helper refuses to proceed until `CHANGELOG.md` contains `## [v<VERSION>]`, so curated release history cannot be skipped.

The public Homebrew cask must point at the final signed/notarized GitHub Release artifact, not an unsigned local development bundle. The intended artifact shape is:

```text
https://github.com/omarpr/lithepg/releases/download/v<VERSION>/LithePG-<VERSION>.zip
```

The release helpers use `LithePG.app.zip` only as a local staging name, then publish `LithePG-<VERSION>.zip` plus `LithePG-<VERSION>.zip.sha256`. The archive still contains `LithePG.app` at its top level. If the notarization wrapper produced an intermediate zip before stapling, rebuild the public zip from the signed, notarized, stapled, and validated `dist/LithePG.app` before upload with the safe local helper:

```sh
LITHEPG_EXPECTED_MARKETING_VERSION=<version> \
./script/create_release_zip.sh dist/LithePG.app dist/LithePG.app.zip
```

The helper re-runs `script/package_verify.sh`, uses `ditto --keepParent` so the `.app` wrapper is preserved, and omits resource forks, extended attributes, quarantine data and ACLs so AppleDouble `._*` entries cannot invalidate the sealed app when a standard ZIP extractor is used. It rejects output paths inside the `.app` bundle, refuses to overwrite an existing zip unless `LITHEPG_RELEASE_ZIP_OVERWRITE=1` (or `true`/`yes`/`approved`) is set, and prints the local SHA-256 plus byte size for review. It does not upload, tag, sign, notarize, push, or contact the network.

Before upload, compute and approve the SHA-256 from the versioned archive that will be attached to the GitHub Release:

```sh
VERSION=1.0.3
shasum -a 256 "dist/LithePG-${VERSION}.zip"
```

Use that approved local digest for `LITHEPG_RELEASE_ZIP_SHA256`, the final GitHub Release copy, and the repository-local draft cask template at `packaging/homebrew/lithepg.rb`:

1. Confirm the prepared `version "1.0.0"` matches the release version and tag.
2. Replace `sha256 "REPLACE_WITH_SHA256"` with the approved local `shasum -a 256` digest.
3. Confirm the `url` still matches the GitHub Release artifact path.
4. Confirm the cask token and public metadata keep `cask "lithepg" do`, `name "LithePG"`, `desc "Lean PostgreSQL client with local-first AI"`, and `homepage "https://www.lithepg.app/"`.
5. Confirm the cask supports the same public macOS floor as the app bundle with `depends_on macos: :sonoma`.
6. Confirm the valid uninstall quit gate remains `uninstall quit: "dev.omarpr.lithepg"`.
7. Confirm the cask installs `app "LithePG.app"`.
8. Confirm the `zap trash:` stanza includes both local cleanup paths: `~/Library/Application Support/LithePG` and `~/Library/Preferences/dev.omarpr.lithepg.plist`.
9. Run `ruby -c packaging/homebrew/lithepg.rb` for template syntax.
10. If Omar has provided the external tap target, copy the cask into that tap and run Homebrew checks there, for example `brew style --cask Casks/lithepg.rb` and `brew audit --cask --new --strict Casks/lithepg.rb`.

Stop before pushing to or creating any external Homebrew tap. Omar must explicitly provide the tap target and publication instructions; do not infer them from the main repository or from the cask token.

After the final versioned archive and checksum are uploaded, verify a fresh download from GitHub as a separate final confirmation that the public URL serves the approved bytes:

```sh
VERSION=1.0.0
curl -L -o "/tmp/LithePG-${VERSION}.zip" \
  "https://github.com/omarpr/lithepg/releases/download/v${VERSION}/LithePG-${VERSION}.zip"
curl -L -o "/tmp/LithePG-${VERSION}.zip.sha256" \
  "https://github.com/omarpr/lithepg/releases/download/v${VERSION}/LithePG-${VERSION}.zip.sha256"
cd /tmp && shasum -a 256 -c "LithePG-${VERSION}.zip.sha256"
```

If the fresh-download hash differs from the approved local digest already used by `LITHEPG_RELEASE_ZIP_SHA256` and the cask, stop and resolve the uploaded artifact before publishing the tap update.

## Fast v1.0.0 publication preflight

Before attempting the external publication steps, run the fast release blocker summary:

```sh
./script/v10_release_gate.sh
```

The helper defaults to version `1.0.0`; `--version` accepts an explicit SemVer `major.minor.patch` value. It is fast on purpose and checks, without printing secrets or digests:

- Git state: clean working tree, `v0.5` tag present locally and an existing `v<version>` tag pointing at `HEAD` (or no release tag yet). Remote tag checks are opt-in via `--check-remote` or `LITHEPG_CHECK_REMOTE_TAGS=1`; network failures report as unknown without blocking, but a confirmed missing `origin` `v0.5` blocks.
- Release copy: no unresolved `REPLACE_WITH_*` placeholders and the approved SHA-256 present as an exact digest token.
- The public zip artifact: a versioned `LithePG-<version>.zip` basename (the legacy local staging name remains accepted), regular file, correct top-level bundle structure with no stray entries, valid ICNS icon, `CodeResources` present, strict `codesign --verify` pass, signature identifier `dev.omarpr.lithepg`, Hardened Runtime flag and a SHA-256 match against the approved digest.
- The Homebrew cask: token, version, URL, verified URL, metadata, uninstall quit gate, app stanza, macOS floor, zap paths, Ruby syntax and `sha256` all match the release.

It does **not** run the Swift tests, package, signing or notarization gates; those still run separately below.

By default, the placeholder scan checks `docs/releases/v1.0-draft.md`, `packaging/homebrew/lithepg.rb`, and the canonical root `SECURITY.md`. To test alternate release/cask files, set `LITHEPG_RELEASE_COPY_PATH` or `LITHEPG_HOMEBREW_CASK_PATH`; to scan an alternate security policy, set `LITHEPG_SECURITY_DOC_PATH`. Each path may be relative to the repository root or absolute. The helper may print the configured paths, but it does not print secret/contact/tap environment values or SHA-256 digest values.

The helper also blocks publication until the final public release zip is present, has the expected bundle structure, and its digest matches the approved value:

| Variable | Expected state |
| --- | --- |
| `LITHEPG_RELEASE_ZIP_PATH` | Path to the final public artifact; release scripts use `dist/LithePG-<version>.zip`, while `dist/LithePG.app.zip` remains the accepted local staging default. It must be a regular file rather than a symlink. |
| `LITHEPG_RELEASE_ZIP_SHA256` | Approved expected 64-hex SHA-256 digest for the exact public zip artifact. |

Any failed artifact, release-copy or cask check above makes the preflight exit non-zero. Failure output is redacted: it never prints expected or actual digests, cask values, signing identifiers, symlink targets or archive contents.

The helper also checks these external inputs without printing their values:

| Variable | Expected state |
| --- | --- |
| `LITHEPG_CODESIGN_IDENTITY` | Set to the Apple Developer Application signing identity. |
| `LITHEPG_NOTARY_PROFILE` | Set to the `notarytool` keychain profile name. |
| `LITHEPG_SECURITY_CONTACT` | Set to the approved public security-contact destination. |
| `LITHEPG_HOMEBREW_TAP` | Set to the approved external Homebrew tap target. |
| `LITHEPG_GITHUB_ACTIONS_READY` | Boolean-style approval that GitHub Actions push/PR/manual workflow status and required account settings are ready for public launch (`true`, `yes`, `1`, or `approved`). |
| `LITHEPG_RELEASE_COPY_APPROVED` | Boolean-style approval (`true`, `yes`, `1`, or `approved`). |
| `LITHEPG_PUBLICATION_APPROVED` | Boolean-style explicit publication approval (`true`, `yes`, `1`, or `approved`). |

All three approval variables default to empty and therefore fail closed. Set
them explicitly for each release invocation after reviewing the corresponding
gate; do not store approved defaults in the release script.

Missing or false inputs make the helper exit non-zero with a `v1.0.0 publication blocked` summary. A passing fast preflight only means the quick local/tag facts and external approvals are present; still run the full local gate commands below before tagging or publishing.

## Making the GitHub repository public

The repository ruleset protects the default branch, GitHub Actions requires
immutable action SHAs, and `.github/workflows/codeql.yml` listens for GitHub's
`public` event so the first Swift CodeQL analysis starts when visibility
changes. Immediately after making the repository public, enable private
vulnerability reporting and verify the setting:

```sh
gh api --method PUT repos/omarpr/lithepg/private-vulnerability-reporting
gh api repos/omarpr/lithepg/private-vulnerability-reporting
```

GitHub does not expose that setting while this repository is private. Do not
claim that private vulnerability reporting is enabled until the verification
request returns `enabled: true`. The email address in root `SECURITY.md` remains
the fallback reporting path.

Then confirm the `CodeQL` workflow completed successfully and that the active
`main-protection` ruleset still requires pull requests, verified signatures,
non-fast-forward protection and CodeQL results. Run
`./script/test_ci_security.sh` locally to reject mutable action refs or an
unpinned Semgrep install before pushing workflow changes.

## v1.0.0 binary-publication gate

The source tag and binary release are separate. Do not publish a GitHub Release or binary artifact until all non-external gates pass and Omar approves the public release copy:

- `script/v10_release_gate.sh` reports the fast preflight is clear.
- Full `swift test`.
- Environment-gated live database tests when their test databases are available.
- Package verification.
- Signed/notarized validation when credentials are available.
- Release notes/README/security/contribution docs reviewed for public users and no secrets.
