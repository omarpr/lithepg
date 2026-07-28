import Foundation

/// Pure, credential-free description of a pasted Neon Postgres connection string.
///
/// Detection is best-effort and read-only: it never stores or echoes the password,
/// and it preserves whatever verified TLS mode `ConnectionConfig` derived from the URL.
public struct NeonConnectionProfile: Sendable, Equatable, CustomStringConvertible {
  public let host: String
  public let endpointID: String?
  public let database: String
  public let username: String
  public let isPooled: Bool
  public let suggestedName: String
  public let tlsMode: ConnectionConfig.TLSMode

  /// The TLS mode LithePG should preselect for this connection.
  ///
  /// Neon serves publicly rooted certificates, so `verifyFull` always succeeds against it, but
  /// Neon hands out `?sslmode=require` URLs. Parsed literally that yields `.require`, which
  /// encrypts without authenticating the server. Since verification is known to work here,
  /// recommend it rather than leaving pasted Neon URLs merely encrypted.
  ///
  /// An explicit `sslmode=disable` is left alone: that is a stated choice, not a default to
  /// fill in. `tlsMode` continues to report what the URL literally said.
  public var recommendedTLSMode: ConnectionConfig.TLSMode {
    switch tlsMode {
    case .prefer, .require, .verifyFull: .verifyFull
    case .disable: .disable
    }
  }

  /// Convenience for callers holding only a URL. Returns nil when the host is not Neon, so
  /// they can fall back to the mode the URL itself specifies.
  public static func recommendedTLSMode(forURL url: String) -> ConnectionConfig.TLSMode? {
    detect(url: url)?.recommendedTLSMode
  }

  public var description: String {
    "NeonConnectionProfile(host: \(host), endpointID: \(endpointID ?? "nil"), database: \(database), username: \(username), isPooled: \(isPooled), suggestedName: \(suggestedName), tlsMode: \(tlsMode))"
  }

  public static func detect(url: String) -> NeonConnectionProfile? {
    guard let config = try? ConnectionConfig(url: url) else { return nil }
    let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard isNeonHost(host) else { return nil }

    let firstLabel = host.split(separator: ".", maxSplits: 1).first.map(String.init) ?? host
    let isPooled = firstLabel.hasSuffix("-pooler") || host.contains("-pooler.")
    let endpointLabel = isPooled && firstLabel.hasSuffix("-pooler")
      ? String(firstLabel.dropLast("-pooler".count))
      : firstLabel
    let endpointID = endpointLabel.hasPrefix("ep-") ? endpointLabel : nil
    let suggestedName = "Neon - \(config.database)"

    return NeonConnectionProfile(
      host: host,
      endpointID: endpointID,
      database: config.database,
      username: config.username,
      isPooled: isPooled,
      suggestedName: suggestedName,
      tlsMode: config.tlsMode
    )
  }

  private static func isNeonHost(_ host: String) -> Bool {
    host == "neon.tech" || host.hasSuffix(".neon.tech")
  }
}
