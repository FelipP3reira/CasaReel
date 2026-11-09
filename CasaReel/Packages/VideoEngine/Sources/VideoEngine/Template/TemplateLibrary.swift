import CryptoKit
import Domain
import Foundation

/// A downloaded template: `{"payload": base64(spec JSON bytes), "signature": base64(Ed25519(payload))}`.
/// Signing the exact bytes avoids depending on a canonical JSON form shared with the server.
public struct TemplatePackage: Codable, Sendable {
    public let payload: Data
    public let signature: Data

    public init(payload: Data, signature: Data) {
        self.payload = payload
        self.signature = signature
    }
}

/// Bundled templates are trusted as part of the signed app; downloaded ones must carry a valid signature.
public struct TemplateLibrary: Sendable {
    public static let bundledSlugs = ["classic-clean", "cinematic-soft", "dynamic-social"]

    public private(set) var specs: [TemplateSpec]
    private let verificationKey: Curve25519.Signing.PublicKey?

    /// - Parameter verificationKey: raw Ed25519 public key for downloaded templates; `nil` accepts bundled ones only.
    public init(verificationKey: Data? = nil) throws(TemplateError) {
        self.verificationKey = try verificationKey.map { key throws(TemplateError) in
            do { return try Curve25519.Signing.PublicKey(rawRepresentation: key) } catch { throw .malformed }
        }
        specs = try Self.bundledSlugs.map { slug throws(TemplateError) in
            guard let url = Bundle.module.url(forResource: slug, withExtension: "json", subdirectory: "Templates"),
                  let data = try? Data(contentsOf: url)
            else { throw .malformed }
            return try TemplateSpec.decode(data)
        }
    }

    public func spec(for slug: TemplateSlug) -> TemplateSpec? {
        specs.first { $0.slug == slug }
    }

    /// Verifies and adds a downloaded template, replacing an older version of the same slug.
    @discardableResult
    public mutating func install(_ package: TemplatePackage) throws(TemplateError) -> TemplateSpec {
        let spec = try Self.verify(package, with: verificationKey)
        if let index = specs.firstIndex(where: { $0.slug == spec.slug }) {
            guard spec.version > specs[index].version else { return specs[index] }
            specs[index] = spec
        } else {
            specs.append(spec)
        }
        return spec
    }

    static func verify(_ package: TemplatePackage, with key: Curve25519.Signing.PublicKey?) throws(TemplateError) -> TemplateSpec {
        guard let key, key.isValidSignature(package.signature, for: package.payload) else { throw .invalidSignature }
        return try TemplateSpec.decode(package.payload)
    }
}
