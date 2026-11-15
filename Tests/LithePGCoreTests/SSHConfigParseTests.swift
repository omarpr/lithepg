import Testing
@testable import LithePGCore

@Suite("SSH target parsing")
struct SSHConfigParseTests {
    typealias SSH = ConnectionConfig.SSHConfig

    @Test("reads user, host and an optional port")
    func readsTarget() throws {
        #expect(try SSH.parse("developer@bastion.example.com") == SSH(host: "bastion.example.com", port: 22, user: "developer"))
        #expect(try SSH.parse(" developer@bastion.example.com:2222 ") == SSH(host: "bastion.example.com", port: 2222, user: "developer"))
    }

    @Test("reads a bracketed IPv6 host with or without a port")
    func readsIPv6() throws {
        #expect(try SSH.parse("developer@[fd00::1]:2200") == SSH(host: "fd00::1", port: 2200, user: "developer"))
        #expect(try SSH.parse("developer@[fd00::1]") == SSH(host: "fd00::1", port: 22, user: "developer"))
    }

    @Test("splits at the last @ so a user may contain one")
    func userWithAt() throws {
        #expect(try SSH.parse("dev@corp@bastion.example.com").user == "dev@corp")
    }

    @Test("rejects malformed targets", arguments: [
        "bastion.example.com", "@bastion.example.com", "developer@", "developer@:22",
        "developer@fd00::1", "developer@[fd00::1", "developer@[fd00::1]x",
    ])
    func rejectsMalformed(raw: String) {
        #expect(throws: SSH.ParseError.invalidFormat) { try SSH.parse(raw) }
    }

    @Test("rejects ports outside 1...65535", arguments: ["0", "65536", "ssh", ""])
    func rejectsBadPort(port: String) {
        #expect(throws: SSH.ParseError.invalidPort(port)) { try SSH.parse("developer@bastion.example.com:\(port)") }
    }

    @Test("rejects values ssh would read as options or that hold spaces")
    func rejectsUnsafe() {
        #expect(throws: SSH.ParseError.unsafeValue("-oProxyCommand=touch")) {
            try SSH.parse("-oProxyCommand=touch@bastion.example.com")
        }
        #expect(throws: SSH.ParseError.unsafeValue("-oProxyCommand=x")) {
            try SSH.parse("developer@-oProxyCommand=x")
        }
        #expect(throws: SSH.ParseError.unsafeValue("dev eloper")) {
            try SSH.parse("dev eloper@bastion.example.com")
        }
    }

    @Test("the target label reads back to the same config")
    func labelRoundTrips() throws {
        for config in [SSH(host: "bastion.example.com", port: 2222, user: "developer"), SSH(host: "fd00::1", port: 22, user: "developer")] {
            #expect(try SSH.parse(config.targetLabel) == config)
        }
    }
}
