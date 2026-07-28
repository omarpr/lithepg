import Testing
import NIOSSL
@testable import LithePGCore

@Suite("TLSFailureClassifier")
struct TLSFailureClassifierTests {
    private struct UnrelatedError: Error {}

    // MARK: - Typed NIOSSL errors

    @Test("classifies a hostname validation failure as a certificate failure")
    func classifiesHostnameFailure() {
        #expect(
            TLSFailureClassifier.isCertificateVerificationFailure(
                NIOSSLExtraError.failedToValidateHostname))
    }

    @Test("classifies an unmatchable server hostname as a certificate failure")
    func classifiesImpossibleHostname() {
        #expect(
            TLSFailureClassifier.isCertificateVerificationFailure(
                NIOSSLExtraError.serverHostnameImpossibleToMatch))
    }

    @Test("classifies an unvalidatable certificate as a certificate failure")
    func classifiesUnableToValidate() {
        #expect(
            TLSFailureClassifier.isCertificateVerificationFailure(
                NIOSSLError.unableToValidateCertificate))
    }

    @Test("classifies a missing certificate as a certificate failure")
    func classifiesNoCertificate() {
        #expect(
            TLSFailureClassifier.isCertificateVerificationFailure(
                NIOSSLError.noCertificateToValidate))
    }

    @Test("does not classify an unrelated error")
    func ignoresUnrelatedError() {
        #expect(TLSFailureClassifier.isCertificateVerificationFailure(UnrelatedError()) == false)
    }

    @Test("does not classify a non certificate NIOSSL error")
    func ignoresNonCertificateNIOSSLError() {
        #expect(
            TLSFailureClassifier.isCertificateVerificationFailure(NIOSSLError.uncleanShutdown)
                == false)
    }

    @Test("does not classify an invalid SNI hostname, which no step down would fix")
    func ignoresInvalidSNIHostname() {
        #expect(
            TLSFailureClassifier.isCertificateVerificationFailure(
                NIOSSLExtraError.invalidSNIHostname) == false)
    }

    @Test("does not classify a handshake failure that carries no certificate signal")
    func ignoresSignallessHandshakeFailure() {
        // A bare sslError with an empty stack says nothing about certificates. Being a
        // handshake failure is not on its own grounds to offer a security downgrade.
        #expect(
            TLSFailureClassifier.isCertificateVerificationFailure(
                NIOSSLError.handshakeFailed(.sslError([]))) == false)
    }

    // MARK: - BoringSSL reason strings
    //
    // BoringSSL reports verification failures through an error stack whose members cannot be
    // constructed outside NIOSSL, so the reason-string matching is tested directly. The inputs
    // below are the strings BoringSSL actually produces, as rendered by
    // BoringSSLInternalError.description.

    @Test("matches the BoringSSL certificate verification reason")
    func matchesCertificateVerifyFailed() {
        #expect(
            TLSFailureClassifier.describesCertificateVerification(
                "Error: 336134278 error:1000007d:SSL routines:OPENSSL_internal:CERTIFICATE_VERIFY_FAILED at ssl/handshake_client.cc:1132"
            ))
    }

    @Test("matches an unknown certificate authority")
    func matchesUnknownCA() {
        #expect(
            TLSFailureClassifier.describesCertificateVerification(
                "Error: 336151598 error:1000412e:SSL routines:OPENSSL_internal:TLSV1_ALERT_UNKNOWN_CA at ssl/tls_record.cc:592"
            ))
    }

    @Test("matches a self signed certificate")
    func matchesSelfSigned() {
        #expect(
            TLSFailureClassifier.describesCertificateVerification(
                "Error: 336134278 error:1000007d:SSL routines:OPENSSL_internal:SELF_SIGNED_CERTIFICATE at ssl/handshake_client.cc:1132"
            ))
    }

    @Test("matches an expired certificate")
    func matchesExpiredCertificate() {
        #expect(
            TLSFailureClassifier.describesCertificateVerification(
                "Error: 336134278 error:1000007d:SSL routines:OPENSSL_internal:CERTIFICATE_EXPIRED at ssl/handshake_client.cc:1132"
            ))
    }

    @Test("matches a bad certificate alert")
    func matchesBadCertificateAlert() {
        #expect(
            TLSFailureClassifier.describesCertificateVerification(
                "Error: 336151600 error:10004130:SSL routines:OPENSSL_internal:SSLV3_ALERT_BAD_CERTIFICATE at ssl/tls_record.cc:592"
            ))
    }

    @Test("does not match a protocol version failure")
    func ignoresVersionFailure() {
        #expect(
            TLSFailureClassifier.describesCertificateVerification(
                "Error: 336130315 error:1000042b:SSL routines:OPENSSL_internal:WRONG_VERSION_NUMBER at ssl/tls_record.cc:242"
            ) == false)
    }

    @Test("does not match a generic handshake failure")
    func ignoresGenericHandshakeFailure() {
        #expect(
            TLSFailureClassifier.describesCertificateVerification(
                "Error: 336151568 error:1000410c:SSL routines:OPENSSL_internal:SSLV3_ALERT_HANDSHAKE_FAILURE at ssl/tls_record.cc:592"
            ) == false)
    }

    @Test("does not match an EOF during handshake")
    func ignoresEOFDuringHandshake() {
        #expect(
            TLSFailureClassifier.describesCertificateVerification("EOF during handshake") == false)
    }

    @Test("does not match an empty reason")
    func ignoresEmptyReason() {
        #expect(TLSFailureClassifier.describesCertificateVerification("") == false)
    }
}
