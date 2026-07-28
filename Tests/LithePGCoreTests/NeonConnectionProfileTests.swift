import Testing
@testable import LithePGCore

@Suite("NeonConnectionProfile")
struct NeonConnectionProfileTests {
  @Test("detects standard Neon compute endpoint URLs")
  func detectsStandardNeonURL() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgresql://omar:***@ep-lively-sun-a1b2c3.us-east-2.aws.neon.tech/appdb?sslmode=require"
      )
    )

    #expect(profile.host == "ep-lively-sun-a1b2c3.us-east-2.aws.neon.tech")
    #expect(profile.endpointID == "ep-lively-sun-a1b2c3")
    #expect(profile.database == "appdb")
    #expect(profile.username == "omar")
    #expect(profile.isPooled == false)
    #expect(profile.suggestedName == "Neon - appdb")
    #expect(profile.tlsMode == .require)
  }

  @Test("detects pooled Neon hosts")
  func detectsPooledNeonURL() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://writer:***@ep-lively-sun-a1b2c3-pooler.us-east-2.aws.neon.tech/neondb?sslmode=require"
      )
    )

    #expect(profile.endpointID == "ep-lively-sun-a1b2c3")
    #expect(profile.isPooled == true)
    #expect(profile.database == "neondb")
    #expect(profile.username == "writer")
  }

  @Test("detects Neon domains even without an endpoint-shaped first label")
  func detectsNeonDomainWithoutEndpointID() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(url: "postgres://u:***@custom.neon.tech/main?sslmode=require")
    )

    #expect(profile.endpointID == nil)
    #expect(profile.host == "custom.neon.tech")
    #expect(profile.suggestedName == "Neon - main")
  }

  @Test("ignores non-Neon Postgres URLs and malformed URLs")
  func ignoresNonNeonAndMalformedURLs() {
    #expect(NeonConnectionProfile.detect(url: "postgres://u:***@db.example.com/main") == nil)
    #expect(NeonConnectionProfile.detect(url: "not a url") == nil)
    #expect(NeonConnectionProfile.detect(url: "mysql://u:***@ep-test.neon.tech/main") == nil)
  }

  @Test("detects modern Neon hosts with a proxy cell segment and channel_binding param")
  func detectsModernNeonHostShape() throws {
    // Shape emitted by neonctl today, verified against a live Neon project:
    // an extra `c-N` proxy-cell label and a channel_binding query parameter.
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgresql://owner:***@ep-odd-paper-a1fxw3hg.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require"
      )
    )

    #expect(profile.host == "ep-odd-paper-a1fxw3hg.c-4.us-east-1.aws.neon.tech")
    #expect(profile.endpointID == "ep-odd-paper-a1fxw3hg")
    #expect(profile.isPooled == false)
    #expect(profile.tlsMode == .require)
  }

  @Test("detects modern pooled Neon hosts with a proxy cell segment")
  func detectsModernPooledNeonHostShape() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgresql://owner:***@ep-odd-paper-a1fxw3hg-pooler.c-4.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require"
      )
    )

    #expect(profile.endpointID == "ep-odd-paper-a1fxw3hg")
    #expect(profile.isPooled == true)
    #expect(profile.tlsMode == .require)
  }

  @Test("profile output excludes password values")
  func profileOutputExcludesPasswords() throws {
    let password = "super-secret"
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://reader:***@ep-long-river-a9b8c7.us-east-1.aws.neon.tech/reporting?sslmode=require"
      )
    )

    let mirrorDump = String(describing: profile)
    #expect(!mirrorDump.contains(password))
    #expect(!profile.suggestedName.contains(password))
  }

  // MARK: - Recommended TLS mode
  //
  // Neon serves publicly rooted certificates, so verify-full always works there. Neon hands
  // out `?sslmode=require` URLs, which parse literally to `.require`. Recommending verify-full
  // keeps pasted Neon URLs authenticated instead of merely encrypted.

  @Test("recommends verify-full for a Neon URL that asks for require")
  func recommendsVerifyFullForRequire() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://u:p@ep-lively-sun-a1b2c3.us-east-2.aws.neon.tech/appdb?sslmode=require"))
    #expect(profile.tlsMode == .require)
    #expect(profile.recommendedTLSMode == .verifyFull)
  }

  @Test("recommends verify-full for a Neon URL that asks for prefer")
  func recommendsVerifyFullForPrefer() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://u:p@ep-lively-sun-a1b2c3.us-east-2.aws.neon.tech/appdb?sslmode=prefer"))
    #expect(profile.recommendedTLSMode == .verifyFull)
  }

  @Test("leaves an already verified Neon URL alone")
  func leavesVerifyFullAlone() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://u:p@ep-lively-sun-a1b2c3.us-east-2.aws.neon.tech/appdb?sslmode=verify-full"
      ))
    #expect(profile.recommendedTLSMode == .verifyFull)
  }

  @Test("respects an explicit request for no encryption")
  func respectsExplicitDisable() throws {
    // Upgrading here would override an explicit choice rather than fill in a default.
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://u:p@ep-lively-sun-a1b2c3.us-east-2.aws.neon.tech/appdb?sslmode=disable"))
    #expect(profile.recommendedTLSMode == .disable)
  }

  @Test("recommends verify-full for a Neon URL with no sslmode at all")
  func recommendsVerifyFullWithoutSSLMode() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://u:p@ep-lively-sun-a1b2c3.us-east-2.aws.neon.tech/appdb"))
    #expect(profile.recommendedTLSMode == .verifyFull)
  }

  @Test("recommends nothing for a host that is not Neon")
  func recommendsNothingForNonNeonHost() {
    #expect(
      NeonConnectionProfile.recommendedTLSMode(
        forURL: "postgres://u:p@db.example.com/appdb?sslmode=require") == nil)
  }

  @Test("recommends verify-full through the URL convenience for a Neon host")
  func recommendsThroughURLConvenience() {
    #expect(
      NeonConnectionProfile.recommendedTLSMode(
        forURL: "postgres://u:p@ep-lively-sun-a1b2c3.us-east-2.aws.neon.tech/appdb?sslmode=require")
        == .verifyFull)
  }
}
