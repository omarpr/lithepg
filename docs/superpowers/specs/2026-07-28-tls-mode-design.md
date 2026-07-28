# TLS Mode Design

**Date:** 2026-07-28
**Status:** Approved

## Problem

`ConnectionConfig.TLSMode` has exactly two cases, `disable` and `verifyFull`. There is no mode
that encrypts the connection without verifying the server certificate, which is the mode libpq
reaches for by default and the mode every comparable GUI client ships with.

Two consequences follow.

**The CA certificate field is a forced workaround.** The field itself is optional. Nothing in
`ConnectSheet.connectDisabled` requires it, and a server with a publicly rooted certificate
connects with the field blank. But the moment the server certificate is not publicly rooted, and
that covers Docker Postgres, self-hosted instances, and anything behind an internal CA, the user
has only two options: locate the server CA PEM and type a filesystem path, or switch the toggle
off, which is full cleartext rather than unverified encryption. Neither is what the user wants.

**URL parsing diverges from libpq in both directions.** `ConnectionConfig.tlsMode(from:host:)`
collapses six libpq sslmode values onto two:

- `allow` and `prefer` become `disable`. libpq attempts TLS for both. A pasted
  `?sslmode=prefer` URL for a remote host therefore travels in cleartext, a silent downgrade.
- `require` becomes `verifyFull`. Providers hand out `?sslmode=require` URLs, and holding them
  to a stricter bar than the string requests is why self-hosted connections fail on first try.

## Design

### Core mode enum

`ConnectionConfig.TLSMode` gains two cases:

```swift
public enum TLSMode: Sendable, Equatable {
    case disable      // no encryption
    case prefer       // encrypt if the server offers it, otherwise cleartext
    case require      // encrypt always, no certificate check
    case verifyFull   // encrypt, verify chain and hostname
}
```

No custom fallback logic is needed for `prefer`. PostgresNIO's
`PostgresConnection.Configuration.TLS` already exposes `.prefer(NIOSSLContext)` with libpq
semantics: attempt TLS, fall back to an insecure connection if the server refuses. See
`PostgresConnection+Configuration.swift:18-22` in the postgres-nio checkout.

`PostgresConnector.makeTLS` becomes a four way switch:

| Mode | `certificateVerification` | `trustRoots` | PostgresNIO case |
| --- | --- | --- | --- |
| `disable` | n/a | n/a | `.disable` |
| `prefer` | `.none` | default | `.prefer(context)` |
| `require` | `.none` | default | `.require(context)` |
| `verifyFull` | `.fullVerification` (default) | pinned file or system default | `.require(context)` |

The existing pinned root certificate handling, including the readability preflight and the
BoringSSL routing comment, applies only to `verifyFull`. Certificate verification is off in
`prefer` and `require`, so a pinned root supplied alongside them would be silently ignored.
Rather than leave that implicit, `ConnectionConfig.init` normalizes `pinnedRootCertificatePath`
to `nil` whenever `tlsMode` is not `verifyFull`. The stored value then always reflects what will
actually be used, which is directly testable and cannot surprise a caller. The CLI rejects the
combination earlier with a usage error, and the UI hides the field outside **Verify**, so
normalization is a backstop rather than the primary guard.

`defaultTLSMode(forHost:)` is unchanged. Loopback hosts default to `disable`, remote hosts
default to `verifyFull`.

### URL sslmode mapping

| URL value | Current | New | Note |
| --- | --- | --- | --- |
| `disable` | `disable` | `disable` | |
| `allow` | `disable` | `prefer` | Documented divergence, see below |
| `prefer` | `disable` | `prefer` | Fixes the silent cleartext downgrade |
| `require` | `verifyFull` | `require` | Stops over promising |
| `verify-ca` | `verifyFull` | `verifyFull` | Still collapsed, see scope |
| `verify-full` | `verifyFull` | `verifyFull` | |
| absent | host default | host default | |
| anything else | `ParseError.unsupportedSSLMode` | unchanged | |

libpq's `allow` tries cleartext first and TLS only if that fails. PostgresNIO offers no such
ordering, so `allow` maps to `prefer`, which attempts TLS first. The observable outcome differs
only in preference order, and both end up encrypted when the server supports TLS. This is a
deliberate, documented divergence.

### UI

The boolean toggle in `ConnectSheet` becomes a four row picker:

- **Off**, caption "No encryption."
- **Prefer**, caption "Encrypt if the server supports it."
- **Encrypt only**, caption "Encrypts, but does not check the server certificate."
- **Verify**, caption "Checks the server certificate and hostname. Uses PostgreSQL verify-full."

Four rows rather than three because with genuine `prefer` support a URL carrying
`?sslmode=prefer` has no honest three row representation.

Dependent UI:

- The CA certificate path field and its file chooser appear only for **Verify**.
- The cleartext warning fires for **Off** on a remote host, as today, and additionally for
  **Prefer** on a remote host, because prefer can legitimately land on cleartext. The Prefer
  wording differs: "May fall back to cleartext if the server refuses TLS."
- SSH tunneling stays mutually exclusive with any mode other than **Off**. Selecting a mode
  other than Off clears the SSH toggle, and enabling SSH forces the mode to Off. This preserves
  the current restriction rather than relaxing it.

Picker state derives from the parsed URL in URL input mode and from the host default in fields
mode, matching how the toggle initializes today.

### Step down affordance

New `TLSFailureClassifier` in `LithePGCore`:

```swift
public enum TLSFailureClassifier {
    public static func isCertificateVerificationFailure(_ error: any Error) -> Bool
}
```

It matches `NIOSSLError.handshakeFailed` carrying a BoringSSL certificate verification error
code, and `NIOSSLExtraError.failedToValidateHostname`. Everything else returns `false`.

When a connection attempt in `verifyFull` fails and the classifier returns `true`, the error
banner gains a **Retry with encryption only** action. Rules:

- The offer appears only for positively identified verification failures. A generic handshake
  error, a timeout, or a network error gets no offer. A transient failure must never train the
  user to click a downgrade.
- The retry is one explicit user action and applies to that connection attempt only. Nothing is
  downgraded automatically.
- On retry the picker moves to **Encrypt only**, so a connection saved afterwards records the
  mode actually in effect rather than the mode originally requested.

### Persistence

`SavedConnectionMetadata.tlsMode` is a string label. `AppState.tlsMode(fromSavedLabel:)` gains
`"prefer"` and `"require"` alongside the existing `"disable"` and `"verify-full"`. Existing rows
keep loading unchanged, so no migration is required.

One way door worth recording: a connection saved by this build with a `prefer` or `require`
label throws `PersistenceError.unsupportedTLSMode` on an older build.

### CLI

`--tls` is removed and replaced by `--tls-mode <disable|prefer|require|verify-full>`. This is a
breaking change to the CLI surface, accepted deliberately.

Validation in `Args.parse`:

- `--tls-mode` with a value outside the four accepted strings is a usage error.
- `--tls-ca` requires `--tls-mode verify-full`. Combining it with any other mode is a usage
  error, because the pinned root would otherwise be silently ignored.
- `--tls-mode verify-full` together with `--ssh` stays rejected, as today.
- `--tls-mode disable` together with `--ssh` is allowed.
- With no `--tls-mode`, the mode comes from the URL sslmode or the host default.

The usage string and README:100 are updated to match.

## Out of scope

`verify-ca`, meaning verify the chain but skip hostname verification, stays collapsed onto
`verifyFull`. NIOSSL supports it through `certificateVerification = .noHostnameVerification`,
and it is the correct mode for a pinned internal CA reached by IP address where the hostname
cannot match. There is no demonstrated need yet and it would add a fifth picker row. This is a
deliberate omission, not an oversight.

## Testing

- `ConnectionConfigTests`: all six sslmode strings, absent sslmode for loopback and remote
  hosts, unsupported sslmode still throwing.
- `PostgresConnectorTests`: each of the four `makeTLS` branches, and the pinned root preflight
  still throwing for an unreadable path under `verifyFull`.
- `ConnectionConfigTests`: a pinned root path normalizes to `nil` under `disable`, `prefer`, and
  `require`, and survives under `verifyFull`.
- `TLSFailureClassifierTests`: hostname validation failure and certificate verification
  handshake failure classify true, generic handshake failure and a non NIOSSL error classify
  false.
- `ConnectSheetPresentationTests`: picker selection state, CA field visibility per mode,
  cleartext warning text per mode and host, SSH mutual exclusion in both directions.
- `AppStateTests`: label round tripping for all four modes, and that existing `"disable"` and
  `"verify-full"` labels still load.
- CLI parse tests for each validation rule above.

## Security posture

`require` and `prefer` encrypt without authenticating the server, so both are vulnerable to an
active machine in the middle. This is a real reduction in guarantee compared to `verifyFull`.
It is nonetheless an improvement on the current state, where the only escape from a failing
`verifyFull` is `disable`, which offers no confidentiality at all. The default for remote hosts
stays `verifyFull`, every weaker mode is an explicit user choice, and the step down affordance
requires a deliberate click on a positively identified certificate failure.
