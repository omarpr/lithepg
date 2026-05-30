# Releasing LithePG

LithePG release artifacts are local-first macOS app bundles. Signing and notarization require Omar-controlled Apple Developer credentials; those credentials must stay in the local keychain or environment and must never be committed.

## Local unsigned package verification

Build and verify the stripped app bundle:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./script/build_and_run.sh --package
./script/package_verify.sh dist/LithePG.app
```

For the final v1.0 candidate, do not rely on the current latest git tag to fill
`CFBundleShortVersionString`: the package builder derives that field from the
latest tag unless `LITHEPG_MARKETING_VERSION` is set. Build the candidate with
the intended marketing version, then verify the app bundle metadata with the
expected-version gate before any signing or notarization step:

```sh
LITHEPG_MARKETING_VERSION=1.0 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./script/build_and_run.sh --package

LITHEPG_EXPECTED_MARKETING_VERSION=1.0 \
./script/package_verify.sh dist/LithePG.app
```

If Omar chooses an explicit release build number for the candidate, set and
verify that number the same way:

```sh
LITHEPG_MARKETING_VERSION=1.0 \
LITHEPG_BUILD_VERSION=<build-number> \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./script/build_and_run.sh --package

LITHEPG_EXPECTED_MARKETING_VERSION=1.0 \
LITHEPG_EXPECTED_BUILD_VERSION=<build-number> \
./script/package_verify.sh dist/LithePG.app
```

The verifier checks:

- `Contents/MacOS/LithePGApp` exists and is executable.
- `Contents/Info.plist` has the expected executable, bundle identifier, bundle name, package type, numeric release/build version fields, minimum system version, and principal class.
- If `LITHEPG_EXPECTED_MARKETING_VERSION` or `LITHEPG_EXPECTED_BUILD_VERSION` is set, the corresponding bundle metadata exactly matches the expected value.
- The packaged executable stays below the 50 MiB hard cap.

An unsigned/ad-hoc-signed local bundle is only a development artifact. Do not publish it as a public v1.0 release.

## Signed + notarized release path

`script/sign_and_notarize.sh` is the credential-gated wrapper for public macOS distribution. It expects a package produced by `script/build_and_run.sh --package` and reads configuration from environment variables only:

| Variable | Purpose |
| --- | --- |
| `LITHEPG_CODESIGN_IDENTITY` | Apple Developer Application signing identity for `codesign`. |
| `LITHEPG_NOTARY_PROFILE` | `xcrun notarytool` keychain profile name. |
| `LITHEPG_ENTITLEMENTS` | Optional entitlements override; defaults to `Sources/LithePGApp/LithePGApp.entitlements`. |
| `LITHEPG_NOTARY_ZIP` | Optional zip output path; defaults to `dist/LithePG-notary.zip`. |

Check the configuration without signing or submitting anything:

```sh
LITHEPG_CODESIGN_IDENTITY="Developer ID Application: Example" \
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

## GitHub Release artifact and Homebrew cask metadata

The draft GitHub Release copy lives at [`docs/releases/v1.0-draft.md`](releases/v1.0-draft.md). Treat it as review material only until Omar approves the release text, all `REPLACE_WITH_*` placeholders are resolved, and the signed/notarized artifact is ready to attach.

The public Homebrew cask must point at the final signed/notarized GitHub Release artifact, not an unsigned local development bundle. The intended artifact shape is:

```text
https://github.com/omarpr/lithepg/releases/download/v<VERSION>/LithePG.app.zip
```

Use `LithePG.app.zip` as the public zip name for the release attachment. If the notarization wrapper produced an intermediate zip before stapling, rebuild the public zip from the signed, notarized, stapled, and validated `dist/LithePG.app` before upload with the safe local helper:

```sh
./script/create_release_zip.sh dist/LithePG.app dist/LithePG.app.zip
```

The helper re-runs `script/package_verify.sh`, uses `ditto --keepParent` so the `.app` wrapper is preserved, rejects output paths inside the `.app` bundle, refuses to overwrite an existing zip unless `LITHEPG_RELEASE_ZIP_OVERWRITE=1` (or `true`/`yes`/`approved`) is set, and prints the local SHA-256 plus byte size for review. It does not upload, tag, sign, notarize, push, or contact the network.

Before upload, compute and approve the SHA-256 from the local final `LithePG.app.zip` that will be attached to the GitHub Release:

```sh
shasum -a 256 dist/LithePG.app.zip
```

Use that approved local digest for `LITHEPG_RELEASE_ZIP_SHA256` and for the repository-local draft cask template at `packaging/homebrew/lithepg.rb`:

1. Replace `version "REPLACE_WITH_VERSION"` with the release version, for example `version "1.0"` unless Omar chooses a different public version.
2. Replace `sha256 "REPLACE_WITH_SHA256"` with the approved local `shasum -a 256` digest.
3. Confirm the `url` still matches the GitHub Release artifact path.
4. Run `ruby -c packaging/homebrew/lithepg.rb` for template syntax.
5. If Omar has provided the external tap target, copy the cask into that tap and run Homebrew checks there, for example `brew style --cask Casks/lithepg.rb` and `brew audit --cask --new --strict Casks/lithepg.rb`.

Stop before pushing to or creating any external Homebrew tap. Omar must explicitly provide the tap target and publication instructions; do not infer them from the main repository or from the cask token.

After the final `LithePG.app.zip` is uploaded, hash a fresh download from GitHub as a separate final confirmation that the public URL serves the approved bytes:

```sh
VERSION=1.0
curl -L -o /tmp/LithePG.app.zip \
  "https://github.com/omarpr/lithepg/releases/download/v${VERSION}/LithePG.app.zip"
shasum -a 256 /tmp/LithePG.app.zip
```

If the fresh-download hash differs from the approved local digest already used by `LITHEPG_RELEASE_ZIP_SHA256` and the cask, stop and resolve the uploaded artifact before publishing the tap update.

## Fast v1.0 publication preflight

Before attempting the external publication steps, run the fast release blocker summary:

```sh
./script/v10_release_gate.sh
```

The helper defaults to version `1.0`; pass `--version <version>` only when checking a different public version. It is intentionally fast: it reports the current git branch/status, verifies local tag readiness (`v0.5` present and `v<version>` absent), blocks on a dirty working tree, scans release-publication text/templates for unresolved `REPLACE_WITH_*` placeholders, verifies the local final public zip artifact exists and matches the approved SHA-256, verifies the placeholder-free Homebrew cask `version` matches the requested `v<version>` release (for example, `version "1.0"` for `v1.0`) and its `sha256` matches that same approved digest, and does not contact `origin` by default. If a remote tag check is desired, opt in with `--check-remote` or `LITHEPG_CHECK_REMOTE_TAGS=1`; the remote tag check verifies `origin` still has the last public milestone tag (`v0.5`) and does not yet have `v<version>`. Remote/network failures are reported as unknown and do not block the fast check, but a confirmed missing `origin` `v0.5` tag blocks publication. It does **not** run the full Swift test, dogfood, package, signing, or notarization gates.

By default, the placeholder scan checks `docs/releases/v1.0-draft.md`, `packaging/homebrew/lithepg.rb`, root `SECURITY.md`, and `docs/SECURITY.md`. To test alternate release/cask files, set `LITHEPG_RELEASE_COPY_PATH` or `LITHEPG_HOMEBREW_CASK_PATH`; to focus the security-policy scan on one alternate file, set `LITHEPG_SECURITY_DOC_PATH`. Each path may be relative to the repository root or absolute. The helper may print the configured paths, but it does not print secret/contact/tap environment values or SHA-256 digest values.

The helper also blocks publication until the final public release zip is present and its digest matches the approved value:

| Variable | Expected state |
| --- | --- |
| `LITHEPG_RELEASE_ZIP_PATH` | Path to the final public `LithePG.app.zip` artifact; defaults to `dist/LithePG.app.zip`. |
| `LITHEPG_RELEASE_ZIP_SHA256` | Approved expected 64-hex SHA-256 digest for the exact public zip artifact. |

If the zip path is missing, the SHA-256 is missing/invalid, the computed `/usr/bin/shasum -a 256` value does not match, a placeholder-free cask has a missing/mismatched `version`, or a placeholder-free cask has a missing/mismatched `sha256`, the fast preflight exits non-zero. Mismatch/invalid output is redacted and does not print the provided, expected, actual, or cask digest.

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

Missing or false inputs make the helper exit non-zero with a `v1.0 publication blocked` summary. A passing fast preflight only means the quick local/tag facts and external approvals are present; still run the full local gate commands below before tagging or publishing.

## v1.0 gate

Do not tag `v1.0` or publish a GitHub Release until all non-external gates pass and Omar approves the public release copy:

- `script/v10_release_gate.sh` reports the fast preflight is clear.
- Full `swift test`.
- Seeded dogfood check when Docker is available.
- Package verification.
- Signed/notarized validation when credentials are available.
- Release notes/README/security/contribution docs reviewed for public users and no secrets.
