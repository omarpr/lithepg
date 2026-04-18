# LithePG Dogfood Log

Per the roadmap (`docs/superpowers/specs/2026-04-18-roadmap-design.md` §6 v0.3 + §9),
this log captures every time the maintainer reaches for a different Postgres
client. The log starts empty at v0.1 and becomes active from v0.3 (Dogfood-Ready).

## v0.1 — 2026-04-18 — Exit-Criteria Smoke Test

- [x] **Plain loopback** — `.build/debug/lithepg --url postgres://postgres:postgres@localhost:55432/postgres` → `SELECT 1 → 1`, exit 0. Tested against `postgres:16` in Docker.
- [x] **TLS verify-full with pinned CA** — `.build/debug/lithepg --url postgres://postgres:postgres@localhost:5433/postgres --tls --tls-ca /tmp/lithepg-tls/server.crt` → `SELECT 1 → 1`, exit 0. Self-signed cert with SAN `DNS:localhost,IP:127.0.0.1`, routed through BoringSSL via `pinnedRootCertificatePath` because Darwin's SecTrust path rejects self-signed anchors.
- [x] **SSH tunnel** — verified on maintainer's machine via macOS loopback (Remote Login on, authorized own key, tunneled back to local Postgres). Three-part verification all green:
  1. `SSH_TEST_TARGET=omar@localhost:22 swift test --filter SSHTunnelTests` → `openAndClose` passed (tunnel opens, local port listens, closes cleanly).
  2. `POSTGRES_SSH_TEST_TARGET=omar@localhost:22,127.0.0.1:5432 POSTGRES_SSH_TEST_CREDS=omar::minmaxing swift test --filter PostgresConnectorTests.sshTunnelSelect1` → `SELECT 1 → 1` through tunnel.
  3. CLI smoke: `.build/debug/lithepg --url postgres://omar:@127.0.0.1:5432/minmaxing --ssh omar@127.0.0.1:22` → `SELECT 1 → 1`, exit 0.

  The tunnel is driven by `/usr/bin/ssh -N -L <local>:<remoteHost>:<remotePort>` with `ExitOnForwardFailure=yes` and `StrictHostKeyChecking=accept-new`. Proves the escape-hatch path that replaces NIOSSH until a later milestone.

### Pure-Swift verification

`swift package show-dependencies` resolves only `postgres-nio` and its transitive graph (swift-nio, swift-nio-ssl, swift-nio-transport-services, swift-crypto, swift-asn1, swift-log, swift-metrics, swift-service-lifecycle, swift-async-algorithms, swift-collections, swift-atomics, swift-system). `grep -i libpq` → no matches. No C shims authored by LithePG (BoringSSL ships vendored inside `swift-nio-ssl`, which is a conscious trade-off documented in `docs/TECH_STACK.md` §3).

## Switches to Other Tools

*(Log entries start at v0.3.)*
