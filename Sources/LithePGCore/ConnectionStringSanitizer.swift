import Foundation

/// Normalizes connection strings pasted from consoles, docs and terminals.
///
/// Real-world copies rarely arrive clean: Neon's console offers `psql '<url>'`
/// commands and `DATABASE_URL=<url>` env lines, and terminal copies carry
/// trailing newlines or surrounding quotes. All of those fail strict URL
/// parsing, so the connect sheet runs pasted input through this first.
/// Sanitizing never touches the URL body itself; it only removes wrappers.
public enum ConnectionStringSanitizer {
  public static func sanitize(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    // `psql 'postgres://...'` command copies.
    value = strippingPrefix("psql ", from: value)

    // `DATABASE_URL=postgres://...` or `export DATABASE_URL="postgres://..."`
    // env-file and shell copies. Only strip an assignment that sits before the
    // scheme so `=` inside the URL's query string is never touched.
    value = strippingPrefix("export ", from: value)
    if let equals = value.firstIndex(of: "="),
      let schemeRange = value.range(of: "://"),
      equals < schemeRange.lowerBound {
      let key = value[value.startIndex..<equals]
      let keyIsIdentifier = !key.isEmpty
        && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
      if keyIsIdentifier {
        value = String(value[value.index(after: equals)...])
      }
    }

    value = value.trimmingCharacters(in: .whitespacesAndNewlines)

    // Matching surrounding quotes; mismatched quotes are left alone.
    for quote in ["'", "\""] {
      if value.count >= 2, value.hasPrefix(quote), value.hasSuffix(quote) {
        value = String(value.dropFirst().dropLast())
      }
    }

    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func strippingPrefix(_ prefix: String, from value: String) -> String {
    guard value.lowercased().hasPrefix(prefix) else { return value }
    return String(value.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
