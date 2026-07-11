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
}
