import Testing
@testable import LithePGCore

@Suite("Error credential redaction")
struct ErrorRedactionTests {
    @Test("scrubs `password: \"secret\"` shaped substrings")
    func scrubsQuotedPassword() {
        let raw = #"Configuration(host: "db", password: "s3cret!", port: 5432)"#
        let out = ErrorRedaction.redactCredentials(in: raw)
        #expect(!out.contains("s3cret!"))
        #expect(out.contains(#"password: [redacted]"#))
    }

    @Test("scrubs `password=...` (no quotes, no space)")
    func scrubsUnquotedPassword() {
        let raw = "jdbc:postgres://db?user=alice&password=hunter2&sslmode=require"
        let out = ErrorRedaction.redactCredentials(in: raw)
        #expect(!out.contains("hunter2"))
        #expect(out.contains("password=[redacted]"))
    }



    @Test("scrubs password embedded in postgres URLs")
    func scrubsPostgresURLPassword() {
        let raw = "failed to connect to postgres://alice:hunter2@db.example.com:5432/app?sslmode=require"
        let out = ErrorRedaction.redactCredentials(in: raw)
        #expect(!out.contains("hunter2"))
        #expect(out.contains("postgres://alice:[redacted]@db.example.com:5432/app"))
    }

    @Test("matches case-insensitively")
    func caseInsensitive() {
        let raw = #"Config(Password: "LOUD")"#
        let out = ErrorRedaction.redactCredentials(in: raw)
        #expect(!out.contains("LOUD"))
    }

    @Test("leaves credential-free messages untouched")
    func untouchedWhenClean() {
        let raw = "connection refused to host db.example.com:5432"
        let out = ErrorRedaction.redactCredentials(in: raw)
        #expect(out == raw)
    }

    @Test("works on real Error values via `description`")
    func worksOnErrorValues() {
        enum FakeError: Error, CustomStringConvertible {
            case leak
            var description: String { #"FakeError(password: "leakage")"# }
        }
        let out = ErrorRedaction.redactCredentials(in: FakeError.leak)
        #expect(!out.contains("leakage"))
        #expect(out.contains("[redacted]"))
    }
}
