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

    @Test("scrubs postgresql URLs and percent-encoded passwords")
    func scrubsPostgresqlURLPassword() {
        let raw = "failed to connect to postgresql://alice:p%40ss%2Fword@db.example.com/app"
        let out = ErrorRedaction.redactCredentials(in: raw)
        #expect(!out.contains("p%40ss%2Fword"))
        #expect(out.contains("postgresql://alice:[redacted]@db.example.com/app"))
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

    @Test("formats only safe actionable PostgreSQL server fields")
    func formatsPostgresServerMessage() {
        let output = ErrorRedaction.postgresServerMessage(
            message: "for SELECT DISTINCT, ORDER BY expressions must appear in select list",
            sqlState: "42P10",
            position: "151"
        )

        #expect(
            output
                == "for SELECT DISTINCT, ORDER BY expressions must appear in select list · SQLSTATE 42P10 · Position 151"
        )
    }

    @Test("PostgreSQL server formatting tolerates missing optional fields")
    func formatsSparsePostgresServerMessage() {
        #expect(
            ErrorRedaction.postgresServerMessage(
                message: "syntax error",
                sqlState: nil,
                position: nil
            ) == "syntax error"
        )
        #expect(
            ErrorRedaction.postgresServerMessage(
                message: "  ",
                sqlState: "42P10",
                position: nil
            ) == "PostgreSQL rejected the request. · SQLSTATE 42P10"
        )
    }
}
