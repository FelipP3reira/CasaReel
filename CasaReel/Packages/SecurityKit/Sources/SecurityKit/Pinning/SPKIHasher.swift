import CryptoKit
import Foundation
import Security

/// Computes the pin of a certificate: base64(SHA-256(DER SubjectPublicKeyInfo)), the same value as
/// `openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`.
enum SPKIHasher {
    private static let rsaEncryption: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    private static let ecPublicKey: [UInt8] = [0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    private static let curveOIDs: [Int: [UInt8]] = [
        256: [0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07],
        384: [0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x22],
        521: [0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x23],
    ]
    private static let null: [UInt8] = [0x05, 0x00]

    static func pin(for certificate: SecCertificate) -> String? {
        guard let key = SecCertificateCopyKey(certificate) else { return nil }
        return pin(for: key)
    }

    static func pin(for key: SecKey) -> String? {
        guard let spki = subjectPublicKeyInfo(for: key) else { return nil }
        return Data(SHA256.hash(data: spki)).base64EncodedString()
    }

    /// Security.framework exports only the raw key (PKCS#1 for RSA, X9.63 point for EC); rebuild the SPKI around it.
    static func subjectPublicKeyInfo(for key: SecKey) -> Data? {
        guard
            let attributes = SecKeyCopyAttributes(key) as? [String: Any],
            let type = attributes[kSecAttrKeyType as String] as? String,
            let raw = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else { return nil }
        let algorithm: [UInt8]
        if type == String(kSecAttrKeyTypeRSA) {
            algorithm = rsaEncryption + null
        } else if type == String(kSecAttrKeyTypeECSECPrimeRandom) {
            let size = attributes[kSecAttrKeySizeInBits as String] as? Int ?? 0
            guard let curve = curveOIDs[size] else { return nil }
            algorithm = ecPublicKey + curve
        } else {
            return nil
        }
        let bitString = der(tag: 0x03, [0x00] + [UInt8](raw))
        return Data(der(tag: 0x30, der(tag: 0x30, algorithm) + bitString))
    }

    private static func der(tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + derLength(content.count) + content
    }

    private static func derLength(_ length: Int) -> [UInt8] {
        guard length >= 0x80 else { return [UInt8(length)] }
        var bytes: [UInt8] = []
        var value = length
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}
