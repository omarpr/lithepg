import Testing

@Suite("LithePGApp placeholder")
struct PlaceholderTests {
    @Test("target compiles")
    func targetCompiles() {
        #expect(Bool(true))
    }
}
