# LithePG website

Vite + React promotional one-pager for
[www.lithepg.app](https://www.lithepg.app). MUI supplies accessible controls and
icons under a custom theme that preserves the LithePG visual direction.

## Develop locally

From `webapp/`:

```sh
npm install
npm run dev
```

Vite prints the local preview URL. Create and verify the production bundle with:

```sh
npm test
```

The generated static site is written to `webapp/dist/`.

## Deploy to Fly.io

The multi-stage `Dockerfile` builds the Vite site and serves `dist/` through
nginx on port 8080. Fly terminates HTTPS and the Machine may stop when idle.

1. Install `flyctl`, sign in and choose a globally unique app name. The prepared
   name is `lithepg-web`; if it is unavailable, change `app` in `fly.toml`.
2. Create the Fly app without deploying, then deploy from this directory:

   ```sh
   cd webapp
   fly apps create lithepg-web
   fly deploy
   ```

3. Confirm the temporary site at `https://lithepg-web.fly.dev`.
4. Add the purchased hostname and inspect Fly's exact DNS instructions:

   ```sh
   fly certs add www.lithepg.app
   fly certs setup www.lithepg.app
   ```

5. At the DNS provider, create the `www` CNAME Fly reports. Do not mix that CNAME
   with A/AAAA records for the same `www` host.
6. Check certificate issuance with `fly certs check www.lithepg.app`.

The nginx config also redirects the apex `lithepg.app` host to `www`. To enable
that redirect publicly, add the apex certificate and follow Fly's emitted DNS
instructions.

References: [Fly static website guide](https://fly.io/docs/languages-and-frameworks/static/)
and [Fly custom-domain guide](https://fly.io/docs/networking/custom-domain/).

## Homebrew copy

The hero and install section present the Homebrew cask as live. The command is
`brew install --cask omarpr/tap/lithepg` and needs no version pin: Homebrew
installs and upgrades to the latest published release.
