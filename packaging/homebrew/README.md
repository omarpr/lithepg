# LithePG Homebrew cask template

This directory contains draft Homebrew cask metadata for the main LithePG repository. It is **not** an external tap, and nothing here should be pushed to a Homebrew tap until Omar approves the tap target.

## Release artifact assumptions

The cask is intended to install the signed and notarized macOS app zip attached to a GitHub Release:

```text
https://github.com/omarpr/lithepg/releases/download/v<VERSION>/LithePG.app.zip
```

Required inputs before publication:

- Final release version, matching the Git tag and GitHub Release, for example `1.0.0` with tag `v1.0.0`.
- Final signed/notarized `LithePG.app.zip` attached to the GitHub Release.
- SHA-256 of the exact public zip artifact, computed after the release artifact is final.
- Omar-approved Homebrew tap target.

## Maintainer workflow

1. Build, sign, notarize, staple, and validate `LithePG.app` using [`../../docs/RELEASING.md`](../../docs/RELEASING.md).
2. Produce the final public zip named `LithePG.app.zip` and attach it to the GitHub Release only after Omar approves the release copy.
3. Compute the SHA-256 from the final artifact, preferably after downloading it from the release URL:

   ```sh
   VERSION=1.0.0
   curl -L -o /tmp/LithePG.app.zip \
     "https://github.com/omarpr/lithepg/releases/download/v${VERSION}/LithePG.app.zip"
   shasum -a 256 /tmp/LithePG.app.zip
   ```

4. Replace the `version` and `sha256` placeholders in `lithepg.rb`.
5. If Omar has provided a tap target, copy the cask into that tap and run the local Homebrew checks there, for example:

   ```sh
   brew style --cask Casks/lithepg.rb
   brew audit --cask --new --strict Casks/lithepg.rb
   ```

6. Stop before any external publication unless Omar has explicitly confirmed the tap repository and push/release procedure.

For this repository-local template, `ruby -c packaging/homebrew/lithepg.rb` is the minimum syntax check.
