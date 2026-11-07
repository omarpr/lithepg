import Foundation
import NIOCore
import PostgresNIO
import Testing

@testable import LithePGCore

@Suite("PostgresConnector renderCell")
struct RenderCellTests {
  private func cell(
    _ bytes: ByteBuffer?, type: PostgresDataType, name: String = "c"
  ) -> PostgresCell {
    PostgresCell(bytes: bytes, dataType: type, format: .binary, columnName: name, columnIndex: 0)
  }

  private func encoded<T: PostgresNonThrowingEncodable>(_ value: T) -> ByteBuffer {
    var buffer = ByteBuffer()
    value.encode(into: &buffer, context: .default)
    return buffer
  }

  @Test("timestamptz renders as readable UTC instead of raw bytes")
  func timestamptzRendersReadably() {
    // 2026-01-02 03:04:05.500 UTC
    let date = Date(timeIntervalSince1970: 1_767_323_045.5)
    let rendered = PostgresConnector.renderCell(cell(encoded(date), type: .timestamptz))
    #expect(rendered == .text("2026-01-02 03:04:05.500Z"))
  }

  @Test("naive timestamp drops the zone suffix")
  func naiveTimestampDropsZone() {
    let date = Date(timeIntervalSince1970: 1_767_323_045.5)
    var buffer = encoded(date)
    // Same wire representation; the cell type is what differs.
    let rendered = PostgresConnector.renderCell(cell(buffer, type: .timestamp))
    buffer.clear()
    #expect(rendered == .text("2026-01-02 03:04:05.500"))
  }

  @Test("date renders as yyyy-mm-dd")
  func dateRendersAsDay() {
    // Postgres date wire format: Int32 days since 2000-01-01.
    let epoch2000 = Date(timeIntervalSince1970: 946_684_800)
    let target = Date(timeIntervalSince1970: 1_767_312_000)  // 2026-01-02 00:00 UTC
    var buffer = ByteBuffer()
    buffer.writeInteger(Int32(target.timeIntervalSince(epoch2000) / 86_400))
    let rendered = PostgresConnector.renderCell(cell(buffer, type: .date))
    #expect(rendered == .text("2026-01-02"))
  }

  @Test("uuid renders lowercased")
  func uuidRenders() {
    let uuid = UUID(uuidString: "0FA0E5F1-9C2D-4D4B-8E44-6F1B2A3C4D5E")!
    let rendered = PostgresConnector.renderCell(cell(encoded(uuid), type: .uuid))
    #expect(rendered == .text("0fa0e5f1-9c2d-4d4b-8e44-6f1b2a3c4d5e"))
  }

  @Test("null cells stay null regardless of type")
  func nullCellsStayNull() {
    #expect(PostgresConnector.renderCell(cell(nil, type: .timestamptz)) == .null)
    #expect(PostgresConnector.renderCell(cell(nil, type: .uuid)) == .null)
  }

  @Test("undecodable bytes still fall back to a byte-count marker")
  func undecodableFallback() {
    var buffer = ByteBuffer()
    buffer.writeInteger(UInt8(0x01))
    let rendered = PostgresConnector.renderCell(cell(buffer, type: .timestamptz))
    #expect(rendered == .text("<1 bytes>"))
  }

  @Test("UTF-8 text keeps accents")
  func utf8TextKeepsAccents() {
    var buffer = ByteBuffer()
    buffer.writeString("José Muñoz ¿qué?")
    #expect(PostgresConnector.renderCell(cell(buffer, type: .text)) == .text("José Muñoz ¿qué?"))
  }

  @Test("text that is not UTF-8 falls back to Latin-1 instead of replacement characters")
  func nonUTF8TextFallsBackToLatin1() {
    // SQL_ASCII databases pass stored bytes through untouched; these are Latin-1 bytes.
    var buffer = ByteBuffer()
    buffer.writeBytes([0x4A, 0x6F, 0x73, 0xE9, 0x20, 0x4D, 0x75, 0xF1, 0x6F, 0x7A])
    #expect(PostgresConnector.renderCell(cell(buffer, type: .text)) == .text("José Muñoz"))
    #expect(PostgresConnector.renderCell(cell(buffer, type: .varchar)) == .text("José Muñoz"))
  }

  /// PostgreSQL's binary numeric: ndigits, weight, sign, dscale, then base-10000 digits.
  private func numeric(weight: Int16, sign: UInt16 = 0, scale: UInt16, digits: [Int16]) -> ByteBuffer {
    var buffer = ByteBuffer()
    buffer.writeInteger(Int16(digits.count))
    buffer.writeInteger(weight)
    buffer.writeInteger(sign)
    buffer.writeInteger(scale)
    for digit in digits { buffer.writeInteger(digit) }
    return buffer
  }

  @Test("numeric keeps the column's scale, trailing zeros included")
  func numericKeepsScale() {
    func render(_ buffer: ByteBuffer) -> QueryResult.Cell {
      PostgresConnector.renderCell(cell(buffer, type: .numeric))
    }
    #expect(render(numeric(weight: 0, scale: 2, digits: [9480])) == .text("9480.00"))
    #expect(render(numeric(weight: 0, scale: 2, digits: [4165, 5000])) == .text("4165.50"))
    #expect(render(numeric(weight: -1, scale: 2, digits: [500])) == .text("0.05"))
    #expect(render(numeric(weight: 1, sign: 0x4000, scale: 1, digits: [1234, 5678, 9000])) == .text("-12345678.9"))
    #expect(render(numeric(weight: 1, scale: 0, digits: [10])) == .text("100000"))
    #expect(render(numeric(weight: 0, scale: 3, digits: [])) == .text("0.000"))
    #expect(render(numeric(weight: -2, scale: 6, digits: [1200])) == .text("0.000012"))
    #expect(render(numeric(weight: -2, scale: 8, digits: [12])) == .text("0.00000012"))
    #expect(render(numeric(weight: 0, sign: 0xC000, scale: 0, digits: [])) == .text("NaN"))
    #expect(render(numeric(weight: 0, sign: 0xD000, scale: 0, digits: [])) == .text("Infinity"))
    #expect(render(numeric(weight: 0, sign: 0xF000, scale: 0, digits: [])) == .text("-Infinity"))
  }
}
