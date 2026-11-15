import Foundation
import Testing
@testable import LithePGCore

@Suite("JSON syntax tokens")
struct JSONSyntaxTokensTests {
    private func kinds(_ text: String) -> [(String, JSONSyntaxTokens.Kind)] {
        let ns = text as NSString
        return JSONSyntaxTokens.tokens(in: text).map { (ns.substring(with: $0.range), $0.kind) }
    }

    @Test("separates keys, strings, numbers, literals and punctuation")
    func classifies() {
        let result = kinds(#"{"name": "Adjuntas", "n": -1.5e3, "ok": true, "x": null, "list": [0]}"#)
        #expect(result.filter { $0.1 == .key }.map(\.0) == [#""name""#, #""n""#, #""ok""#, #""x""#, #""list""#])
        #expect(result.filter { $0.1 == .string }.map(\.0) == [#""Adjuntas""#])
        #expect(result.filter { $0.1 == .number }.map(\.0) == ["-1.5e3", "0"])
        #expect(result.filter { $0.1 == .literal }.map(\.0) == ["true", "null"])
        #expect(result.filter { $0.1 == .punctuation }.count == 13)  // { } [ ], 5 colons, 4 commas
    }

    @Test("escaped quotes stay inside their string and a key may sit across a newline")
    func escapesAndNewlines() {
        let result = kinds("{\n  \"say \\\"hi\\\"\"\n  : \"a, b: [c]\"\n}")
        #expect(result.map(\.1) == [.punctuation, .key, .punctuation, .string, .punctuation])
    }

    @Test("half-typed JSON still colors what it can")
    func lenient() {
        let result = kinds(#"{"open": "unterminated"#)
        #expect(result.map(\.1) == [.punctuation, .key, .punctuation, .string])
        #expect(result.last?.0 == #""unterminated"#)
    }

    @Test("ranges are UTF-16 offsets")
    func utf16Ranges() {
        let text = #"{"é😀": 1}"#
        let number = JSONSyntaxTokens.tokens(in: text).first { $0.kind == .number }
        #expect(number.map { (text as NSString).substring(with: $0.range) } == "1")
    }

    @Test("only text starting with an object or array is treated as JSON")
    func looksLikeJSON() {
        #expect(JSONSyntaxTokens.looksLikeJSON("  {\"a\": 1}"))
        #expect(JSONSyntaxTokens.looksLikeJSON("[1"))
        #expect(!JSONSyntaxTokens.looksLikeJSON("plain {text}"))
        #expect(!JSONSyntaxTokens.looksLikeJSON(""))
    }
}
