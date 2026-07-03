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
    #expect(profile.tlsMode == .verifyFull)
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
}
