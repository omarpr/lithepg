import Testing
@testable import LithePGCore

@Suite("ConnectionStringSanitizer")
struct ConnectionStringSanitizerTests {
  private let canonical =
    "postgresql://u:p@ep-x-a1b2c3.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require"

  @Test("leaves clean connection strings untouched")
  func leavesCleanStringsUntouched() {
    #expect(ConnectionStringSanitizer.sanitize(canonical) == canonical)
  }

  @Test("trims surrounding whitespace and trailing newlines")
  func trimsWhitespaceAndNewlines() {
    #expect(ConnectionStringSanitizer.sanitize("  \(canonical)  ") == canonical)
    #expect(ConnectionStringSanitizer.sanitize("\(canonical)\n") == canonical)
    #expect(ConnectionStringSanitizer.sanitize("\t\(canonical)\r\n") == canonical)
  }

  @Test("strips matching surrounding quotes")
  func stripsSurroundingQuotes() {
    #expect(ConnectionStringSanitizer.sanitize("'\(canonical)'") == canonical)
    #expect(ConnectionStringSanitizer.sanitize("\"\(canonical)\"") == canonical)
    // Mismatched quotes are left alone rather than half-stripped.
    #expect(ConnectionStringSanitizer.sanitize("'\(canonical)") == "'\(canonical)")
  }

  @Test("strips a leading psql command wrapper")
  func stripsPsqlWrapper() {
    #expect(ConnectionStringSanitizer.sanitize("psql '\(canonical)'") == canonical)
    #expect(ConnectionStringSanitizer.sanitize("psql \"\(canonical)\"") == canonical)
    #expect(ConnectionStringSanitizer.sanitize("psql \(canonical)") == canonical)
  }

  @Test("strips a leading environment-variable assignment")
  func stripsEnvAssignment() {
    #expect(ConnectionStringSanitizer.sanitize("DATABASE_URL=\(canonical)") == canonical)
    #expect(ConnectionStringSanitizer.sanitize("DATABASE_URL='\(canonical)'") == canonical)
    #expect(ConnectionStringSanitizer.sanitize("export DATABASE_URL=\"\(canonical)\"") == canonical)
  }

  @Test("does not mangle equals signs inside the URL itself")
  func preservesQueryEquals() {
    let withParams = canonical + "&channel_binding=require"
    #expect(ConnectionStringSanitizer.sanitize(withParams) == withParams)
  }

  @Test("sanitized console copies parse and detect as Neon")
  func sanitizedVariantsDetectAsNeon() {
    let variants = [
      "\(canonical)\n",
      "'\(canonical)'",
      "psql '\(canonical)'",
      "DATABASE_URL=\(canonical)",
    ]
    for variant in variants {
      let cleaned = ConnectionStringSanitizer.sanitize(variant)
      #expect(NeonConnectionProfile.detect(url: cleaned) != nil, "variant failed: \(variant)")
    }
  }

  @Test("passes through non-URL text unchanged apart from trimming")
  func passesThroughNonURLText() {
    #expect(ConnectionStringSanitizer.sanitize("not a url") == "not a url")
    #expect(ConnectionStringSanitizer.sanitize("") == "")
  }
}
