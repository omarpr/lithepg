# LithePG Homebrew cask template

This directory contains the repository copy of the LithePG cask. Release helpers prepare it here, then copy the validated result to the project-owned `omarpr/tap` repository.

## Release artifact assumptions

The cask is intended to install the signed and notarized macOS app zip attached to a GitHub Release:

```text
https://github.com/omarpr/lithepg/releases/download/v<VERSION>/LithePG-<VERSION>.zip
```

Required inputs before publication:

- Final release version, matching the Git tag and GitHub Release, for example `1.0.0` with tag `v1.0.0`.
- Final `LithePG-<VERSION>.zip` attached to the matching GitHub Release, with `LithePG.app` as its top-level bundle.
- Matching `LithePG-<VERSION>.zip.sha256` checksum sidecar.
- SHA-256 of the exact public zip artifact, computed after the release artifact is final.
- Omar-approved Homebrew tap target.

## Maintainer workflow

1. Build, sign, notarize, staple, and validate `LithePG.app` using [`../../docs/RELEASING.md`](../../docs/RELEASING.md).
2. Run the release helper. It creates a versioned public archive and checksum sidecar, synchronizes the README release block, and attaches both files to the GitHub Release.
3. Compute the SHA-256 from the final artifact, preferably after downloading it from the release URL:

   ```sh
   VERSION=1.0.0
   curl -L -o "/tmp/LithePG-${VERSION}.zip" \
     "https://github.com/omarpr/lithepg/releases/download/v${VERSION}/LithePG-${VERSION}.zip"
   curl -L -o "/tmp/LithePG-${VERSION}.zip.sha256" \
     "https://github.com/omarpr/lithepg/releases/download/v${VERSION}/LithePG-${VERSION}.zip.sha256"
   cd /tmp && shasum -a 256 -c "LithePG-${VERSION}.zip.sha256"
   ```

4. Confirm `lithepg.rb` contains the release version, exact SHA-256 and version-interpolated archive URL.
5. If Omar has provided a tap target, copy the cask into that tap and run the local Homebrew checks there, for example:

   ```sh
   brew style --cask Casks/lithepg.rb
   brew audit --cask --new --strict Casks/lithepg.rb
   ```

6. For previews, confirm the tap copy retains the unnotarized-build caveat. Stable releases must be Developer ID signed and notarized.

For this repository-local template, `ruby -c packaging/homebrew/lithepg.rb` is the minimum syntax check.
