import Foundation
import NIOSSL

/// Decides whether a connection failure was caused by server certificate verification, and so
/// whether stepping down from `.verifyFull` to `.require` could plausibly succeed.
///
/// Deliberately conservative. Anything not positively identified as a certificate problem
/// returns `false`. A false negative costs the user one manual mode change. A false positive
/// offers a security downgrade in response to an unrelated failure, which trains people to
/// click through to weaker encryption whenever anything goes wrong. The second is worse.
public enum TLSFailureClassifier {
    public static func isCertificateVerificationFailure(_ error: any Error) -> Bool {
        if let extra = error as? NIOSSLExtraError {
            switch extra {
            case .failedToValidateHostname, .serverHostnameImpossibleToMatch:
                return true
            default:
                // Notably excludes invalidSNIHostname, which is a malformed request rather than
                // a rejected server certificate. Turning verification off would not fix it.
                return false
            }
        }

        if let sslError = error as? NIOSSLError {
            switch sslError {
            case .unableToValidateCertificate, .noCertificateToValidate:
                return true
            case .handshakeFailed(let boringSSLError):
                return describesCertificateVerification(String(describing: boringSSLError))
            default:
                return false
            }
        }

        return false
    }

    /// BoringSSL reports verification failures through an error stack rather than a typed case,
    /// so the rendered reason text is the only available signal. Match the specific verification
    /// reasons rather than treating every handshake failure as a certificate problem.
    ///
    /// Internal rather than private so it can be tested directly: `BoringSSLInternalError` has no
    /// public initializer, so these strings cannot be reached through a constructed `NIOSSLError`.
    static func describesCertificateVerification(_ description: String) -> Bool {
        let description = description.lowercased()
        let markers = [
            "certificate_verify_failed",
            "certificate verify failed",
            "unknown_ca",
            "bad_certificate",
            "certificate_expired",
            "certificate_revoked",
            "unsupported_certificate",
            "self_signed_certificate",
            "self signed certificate",
            "unable_to_get_issuer",
            "unable_to_verify_leaf_signature",
            "hostname mismatch",
        ]
        return markers.contains { description.contains($0) }
    }
}
