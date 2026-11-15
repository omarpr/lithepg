import Testing
@testable import LithePGCore

@Suite("JSON text formatter")
struct JSONTextFormatterTests {
    @Test("pretty prints nested objects and arrays two spaces per level")
    func prettyPrints() {
        let compact = #"{"municipality":"Adjuntas","tags":["a","b"],"empty":{},"none":[],"n":0}"#
        #expect(JSONTextFormatter.prettyPrinted(compact) == """
            {
              "municipality": "Adjuntas",
              "tags": [
                "a",
                "b"
              ],
              "empty": {},
              "none": [],
              "n": 0
            }
            """)
    }

    @Test("compacting undoes pretty printing")
    func compactRoundTrips() throws {
        let compact = #"{"a":[1,{"b":null}],"c":"x y"}"#
        let pretty = try #require(JSONTextFormatter.prettyPrinted(compact))
        #expect(JSONTextFormatter.compacted(pretty) == compact)
    }

    @Test("strings, numbers and key order are copied exactly")
    func preservesTokens() throws {
        let value = #"{"z":12345678901234567890.50,"a":"say \"hi\", {ok}: [1]","é":"é\\"}"#
        let pretty = try #require(JSONTextFormatter.prettyPrinted(value))
        #expect(pretty.contains(#""z": 12345678901234567890.50"#))
        #expect(pretty.contains(#""a": "say \"hi\", {ok}: [1]""#))
        #expect(pretty.contains(#""é": "é\\""#))
        #expect(pretty.firstRange(of: "\"z\"")!.lowerBound < pretty.firstRange(of: "\"a\"")!.lowerBound)
    }

    @Test("only offers JSON objects and arrays", arguments: [
        "", "plain text", "42", "\"a string\"", "true", "{not json}", "[1,", "{\"a\":1} trailing",
    ])
    func rejectsOtherText(text: String) {
        #expect(!JSONTextFormatter.isFormattable(text))
        #expect(JSONTextFormatter.prettyPrinted(text) == nil)
    }

    @Test("accepts surrounding whitespace")
    func acceptsWhitespace() {
        #expect(JSONTextFormatter.compacted("  [ 1 , 2 ]\n") == "[1,2]")
    }
}
