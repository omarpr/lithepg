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

An unsigned/ad-hoc-signed local bundle is only a development artifact. Do not publish it as a public v1.0.0 release.

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

The notary-submission zip is a credential-gated intermediate artifact, not the public release attachment. `script/sign_and_notarize.sh` refuses to use an existing `LITHEPG_NOTARY_ZIP` path, including a symlink at that path, unless `LITHEPG_NOTARY_ZIP_OVERWRITE` is explicitly approved (`1`, `true`, `yes`, or `approved`); the same guard runs during `--dry-run` so preflight catches stale zip artifacts before real signing/notary execution. After that approval gate passes, real mode may remove and recreate the zip as part of the signing/notarization flow; dry-run still creates no zip.

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

The helper re-runs `script/package_verify.sh`, uses `ditto --keepParent` so the `.app` wrapper is preserved, and omits resource forks, extended attributes, quarantine data and ACLs so AppleDouble `._*` entries cannot invalidate the sealed app when a standard ZIP extractor is used. It rejects output paths inside the `.app` bundle, refuses to overwrite an existing zip unless `LITHEPG_RELEASE_ZIP_OVERWRITE=1` (or `true`/`yes`/`approved`) is set, and prints the local SHA-256 plus byte size for review. It does not upload, tag, sign, notarize, push, or contact the network.

Before upload, compute and approve the SHA-256 from the local final `LithePG.app.zip` that will be attached to the GitHub Release:

```sh
shasum -a 256 dist/LithePG.app.zip
```

Use that approved local digest for `LITHEPG_RELEASE_ZIP_SHA256`, the final GitHub Release copy, and the repository-local draft cask template at `packaging/homebrew/lithepg.rb`:

1. Confirm the prepared `version "1.0.0"` matches the release version and tag.
2. Replace `sha256 "REPLACE_WITH_SHA256"` with the approved local `shasum -a 256` digest.
3. Confirm the `url` still matches the GitHub Release artifact path.
4. Confirm the cask token and public metadata keep `cask "lithepg" do`, `name "LithePG"`, `desc "Lean PostgreSQL client with local-first AI"`, and `homepage "https://www.lithepg.app"`.
5. Confirm the cask supports the same public macOS floor as the app bundle with `depends_on macos: ">= :sonoma"`.
6. Confirm the valid uninstall quit gate remains `uninstall quit: "dev.omarpr.lithepg"`.
7. Confirm the cask installs `app "LithePG.app"`.
8. Confirm the `zap trash:` stanza includes both local cleanup paths: `~/Library/Application Support/LithePG` and `~/Library/Preferences/dev.omarpr.lithepg.plist`.
9. Run `ruby -c packaging/homebrew/lithepg.rb` for template syntax.
10. If Omar has provided the external tap target, copy the cask into that tap and run Homebrew checks there, for example `brew style --cask Casks/lithepg.rb` and `brew audit --cask --new --strict Casks/lithepg.rb`.

Stop before pushing to or creating any external Homebrew tap. Omar must explicitly provide the tap target and publication instructions; do not infer them from the main repository or from the cask token.

After the final `LithePG.app.zip` is uploaded, hash a fresh download from GitHub as a separate final confirmation that the public URL serves the approved bytes:

```sh
VERSION=1.0.0
curl -L -o /tmp/LithePG.app.zip \
  "https://github.com/omarpr/lithepg/releases/download/v${VERSION}/LithePG.app.zip"
shasum -a 256 /tmp/LithePG.app.zip
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
- The public zip artifact: exact `LithePG.app.zip` basename, regular file, correct top-level bundle structure with no stray entries, valid ICNS icon, `CodeResources` present, strict `codesign --verify` pass, signature identifier `dev.omarpr.lithepg`, Hardened Runtime flag and a SHA-256 match against the approved digest.
- The Homebrew cask: token, version, URL, verified URL, metadata, uninstall quit gate, app stanza, macOS floor, zap paths, Ruby syntax and `sha256` all match the release.

It does **not** run the Swift tests, dogfood, package, signing or notarization gates; those still run separately below.

By default, the placeholder scan checks `docs/releases/v1.0-draft.md`, `packaging/homebrew/lithepg.rb`, root `SECURITY.md`, and `docs/SECURITY.md`. To test alternate release/cask files, set `LITHEPG_RELEASE_COPY_PATH` or `LITHEPG_HOMEBREW_CASK_PATH`; to focus the security-policy scan on one alternate file, set `LITHEPG_SECURITY_DOC_PATH`. Each path may be relative to the repository root or absolute. The helper may print the configured paths, but it does not print secret/contact/tap environment values or SHA-256 digest values.

The helper also blocks publication until the final public release zip is present, has the expected bundle structure, and its digest matches the approved value:

| Variable | Expected state |
| --- | --- |
| `LITHEPG_RELEASE_ZIP_PATH` | Path to the final public `LithePG.app.zip` artifact; defaults to `dist/LithePG.app.zip`, must have basename exactly `LithePG.app.zip`, and must be a regular file rather than a symlink. |
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

Missing or false inputs make the helper exit non-zero with a `v1.0.0 publication blocked` summary. A passing fast preflight only means the quick local/tag facts and external approvals are present; still run the full local gate commands below before tagging or publishing.

## v1.0.0 binary-publication gate

The source tag and binary release are separate. Do not publish a GitHub Release or binary artifact until all non-external gates pass and Omar approves the public release copy:

- `script/v10_release_gate.sh` reports the fast preflight is clear.
- Full `swift test`.
- Seeded dogfood check when Docker is available.
- Package verification.
- Signed/notarized validation when credentials are available.
- Release notes/README/security/contribution docs reviewed for public users and no secrets.
