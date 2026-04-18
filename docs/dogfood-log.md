# LithePG Dogfood Log

Per the roadmap (`docs/superpowers/specs/2026-04-18-roadmap-design.md` §6 v0.3 + §9),
this log captures every time the maintainer reaches for a different Postgres
client. The log starts empty at v0.1 and becomes active from v0.3 (Dogfood-Ready).

## v0.1 — 2026-04-18 — Exit-Criteria Smoke Test

- [x] **Plain loopback** — `.build/debug/lithepg --url postgres://postgres:postgres@localhost:55432/postgres` → `SELECT 1 → 1`, exit 0. Tested against `postgres:16` in Docker.
- [x] **TLS verify-full with pinned CA** — `.build/debug/lithepg --url postgres://postgres:postgres@localhost:5433/postgres --tls --tls-ca /tmp/lithepg-tls/server.crt` → `SELECT 1 → 1`, exit 0. Self-signed cert with SAN `DNS:localhost,IP:127.0.0.1`, routed through BoringSSL via `pinnedRootCertificatePath` because Darwin's SecTrust path rejects self-signed anchors.
- [ ] **SSH tunnel** — deferred to maintainer's environment. No SSH-reachable Postgres is available on the build machine. The path is covered by the automated `SSHTunnelTests.openAndClose` and `PostgresConnectorTests.sshTunnelSelect1` integration tests (currently skipped under Swift Testing's `.enabled(if:)` gate, to be run by the maintainer with `SSH_TEST_TARGET` / `POSTGRES_SSH_TEST_TARGET` / `POSTGRES_SSH_TEST_CREDS` exported). CLI equivalent:

  ```
  .build/debug/lithepg \
    --url postgres://user:pass@pg-internal.example.com:5432/db \
    --ssh user@bastion.example.com:22
  ```

### Pure-Swift verification

`swift package show-dependencies` resolves only `postgres-nio` and its transitive graph (swift-nio, swift-nio-ssl, swift-nio-transport-services, swift-crypto, swift-asn1, swift-log, swift-metrics, swift-service-lifecycle, swift-async-algorithms, swift-collections, swift-atomics, swift-system). `grep -i libpq` → no matches. No C shims authored by LithePG (BoringSSL ships vendored inside `swift-nio-ssl`, which is a conscious trade-off documented in `docs/TECH_STACK.md` §3).

## Switches to Other Tools

*(Log entries start at v0.3.)*
