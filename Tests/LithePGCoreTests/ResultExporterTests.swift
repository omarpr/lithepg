import Foundation
import Testing
@testable import LithePGCore

@Suite("ResultExporter")
struct ResultExporterTests {
    private func rowsResult(
        columns: [QueryResult.Column],
        rows: [[QueryResult.Cell]]
    ) -> QueryResult {
        QueryResult(
            columns: columns,
            rows: rows.enumerated().map { QueryResult.Row(id: $0.offset, cells: $0.element) },
            rowCount: rows.count,
            elapsed: .milliseconds(1),
            status: .rows,
            truncated: false
        )
    }

    // MARK: - CSV

    @Test("CSV writes header plus rows with CRLF line endings (RFC 4180)")
    func csvBasic() {
        let result = rowsResult(
            columns: [.init(name: "id", typeName: "int4"), .init(name: "name", typeName: "text")],
            rows: [
                [.text("1"), .text("Ada")],
                [.text("2"), .text("Grace")],
            ]
        )
        let csv = ResultExporter.csv(for: result)
        #expect(csv == "id,name\r\n1,Ada\r\n2,Grace")
    }

    @Test("CSV quotes fields containing comma, quote, or newline and doubles quotes")
    func csvEscaping() {
        let result = rowsResult(
            columns: [.init(name: "note", typeName: "text")],
            rows: [
                [.text("a,b")],
                [.text("say \"hi\"")],
                [.text("line1\nline2")],
            ]
        )
        let csv = ResultExporter.csv(for: result)
        #expect(csv == "note\r\n\"a,b\"\r\n\"say \"\"hi\"\"\"\r\n\"line1\nline2\"")
    }

    @Test("CSV renders NULL cells as empty fields, distinct from empty string which is unquoted too")
    func csvNull() {
        let result = rowsResult(
            columns: [.init(name: "a", typeName: "text"), .init(name: "b", typeName: "text")],
            rows: [
                [.null, .text("x")],
                [.text(""), .null],
            ]
        )
        let csv = ResultExporter.csv(for: result)
        #expect(csv == "a,b\r\n,x\r\n,")
    }

    @Test("CSV for a command/empty result with no columns is an empty string")
    func csvNoColumns() {
        let result = QueryResult(
            columns: [],
            rows: [],
            rowCount: 0,
            elapsed: .milliseconds(0),
            status: .command(tag: "INSERT", affected: 3),
            truncated: false
        )
        #expect(ResultExporter.csv(for: result) == "")
    }

    // MARK: - JSON

    @Test("JSON emits an array of objects keyed by column name in column order")
    func jsonBasic() {
        let result = rowsResult(
            columns: [.init(name: "id", typeName: "int4"), .init(name: "name", typeName: "text")],
            rows: [
                [.text("1"), .text("Ada")],
                [.text("2"), .text("Grace")],
            ]
        )
        let json = ResultExporter.json(for: result)
        #expect(json == "[{\"id\":\"1\",\"name\":\"Ada\"},{\"id\":\"2\",\"name\":\"Grace\"}]")
    }

    @Test("JSON encodes NULL cells as literal null and text cells as strings")
    func jsonNull() {
        let result = rowsResult(
            columns: [.init(name: "a", typeName: "text"), .init(name: "b", typeName: "text")],
            rows: [
                [.null, .text("x")],
            ]
        )
        let json = ResultExporter.json(for: result)
        #expect(json == "[{\"a\":null,\"b\":\"x\"}]")
    }

    @Test("JSON escapes quotes, backslashes, newlines, tabs, and control characters")
    func jsonEscaping() {
        let result = rowsResult(
            columns: [.init(name: "v", typeName: "text")],
            rows: [
                [.text("quote\"slash\\tab\tnewline\nreturn\r\u{0001}")],
            ]
        )
        let json = ResultExporter.json(for: result)
        #expect(json == "[{\"v\":\"quote\\\"slash\\\\tab\\tnewline\\nreturn\\r\\u0001\"}]")
        // The emitted JSON must be valid and decode back to the original string.
        let data = Data(json.utf8)
        let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(decoded?.first?["v"] as? String == "quote\"slash\\tab\tnewline\nreturn\r\u{0001}")
    }

    @Test("JSON escapes column-name keys too")
    func jsonKeyEscaping() {
        let result = rowsResult(
            columns: [.init(name: "weird\"key", typeName: "text")],
            rows: [[.text("v")]]
        )
        let json = ResultExporter.json(for: result)
        #expect(json == "[{\"weird\\\"key\":\"v\"}]")
    }

    @Test("JSON for a result with no rows is an empty array")
    func jsonNoRows() {
        let result = QueryResult(
            columns: [.init(name: "id", typeName: "int4")],
            rows: [],
            rowCount: 0,
            elapsed: .milliseconds(0),
            status: .rows,
            truncated: false
        )
        #expect(ResultExporter.json(for: result) == "[]")
    }

    // MARK: - Markdown (GitHub-flavored table)

    @Test("Markdown emits a GFM table: header, delimiter, then one row per record")
    func markdownBasic() {
        let result = rowsResult(
            columns: [.init(name: "id", typeName: "int4"), .init(name: "name", typeName: "text")],
            rows: [
                [.text("1"), .text("Ada")],
                [.text("2"), .text("Grace")],
            ]
        )
        let md = ResultExporter.markdown(for: result)
        #expect(md == "| id | name |\n| --- | --- |\n| 1 | Ada |\n| 2 | Grace |")
    }

    @Test("Markdown escapes pipe characters and converts newlines to <br>")
    func markdownEscaping() {
        let result = rowsResult(
            columns: [.init(name: "a | b", typeName: "text")],
            rows: [
                [.text("x|y")],
                [.text("line1\nline2")],
                [.text("crlf\r\nhere")],
            ]
        )
        let md = ResultExporter.markdown(for: result)
        #expect(md == "| a \\| b |\n| --- |\n| x\\|y |\n| line1<br>line2 |\n| crlf<br>here |")
    }

    @Test("Markdown renders NULL and empty cells as blank table cells")
    func markdownNull() {
        let result = rowsResult(
            columns: [.init(name: "a", typeName: "text"), .init(name: "b", typeName: "text")],
            rows: [
                [.null, .text("x")],
                [.text(""), .null],
            ]
        )
        let md = ResultExporter.markdown(for: result)
        #expect(md == "| a | b |\n| --- | --- |\n|  | x |\n|  |  |")
    }

    @Test("Markdown for a result with columns but no rows is just header plus delimiter")
    func markdownNoRows() {
        let result = QueryResult(
            columns: [.init(name: "id", typeName: "int4")],
            rows: [],
            rowCount: 0,
            elapsed: .milliseconds(0),
            status: .rows,
            truncated: false
        )
        #expect(ResultExporter.markdown(for: result) == "| id |\n| --- |")
    }

    @Test("Markdown for a command/empty result with no columns is an empty string")
    func markdownNoColumns() {
        let result = QueryResult(
            columns: [],
            rows: [],
            rowCount: 0,
            elapsed: .milliseconds(0),
            status: .command(tag: "INSERT", affected: 3),
            truncated: false
        )
        #expect(ResultExporter.markdown(for: result) == "")
    }

    // MARK: - Format metadata

    @Test("export formats expose stable file extensions and UTI-friendly identifiers")
    func formatMetadata() {
        #expect(ResultExporter.Format.csv.fileExtension == "csv")
        #expect(ResultExporter.Format.json.fileExtension == "json")
        #expect(ResultExporter.Format.markdown.fileExtension == "md")
        #expect(ResultExporter.Format.allCases.count == 3)
    }

    @Test("export(_:as:) dispatches to the matching serializer")
    func exportDispatch() {
        let result = rowsResult(
            columns: [.init(name: "id", typeName: "int4")],
            rows: [[.text("1")]]
        )
        #expect(ResultExporter.export(result, as: .csv) == ResultExporter.csv(for: result))
        #expect(ResultExporter.export(result, as: .json) == ResultExporter.json(for: result))
        #expect(ResultExporter.export(result, as: .markdown) == ResultExporter.markdown(for: result))
    }
}
