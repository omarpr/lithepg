import Foundation

public actor SSHTunnel {
    public let localPort: Int

    private init(localPort: Int) {
        self.localPort = localPort
    }

    public static func open(
        sshHost: String,
        sshPort: Int,
        sshUser: String,
        remoteHost: String,
        remotePort: Int
    ) async throws -> SSHTunnel {
        fatalError("SSHTunnel.open not implemented yet — see Task 6")
    }

    public func close() async {
        // no-op; full implementation in Task 6
    }
}
