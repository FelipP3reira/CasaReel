import Foundation
import Security

/// Throwaway test PKI generated with OpenSSL (P-256). No private keys are kept; certificates only.
/// - ca: "CasaReel Test Root CA", valid 10 years
/// - good / other: leafs for api.test.casareel.example with different keys, valid 1 year
/// - shortLived: leaf valid for 1 day only (expired when the verify date is moved forward)
enum TestCertificates {
    static let host = "api.test.casareel.example"
    static let goodPin = "V0Uk+8E5Wf+Fp/M/BnLx8WvPQq/zPkxlbkL7uOp8k+Q="
    static let otherPin = "HtEfRlb9dAYt80eSyaQLLM1N/+NNbw9TgjJDjz9Jy98="

    static let ca = certificate("MIIBZjCCAQugAwIBAgIUfURC5qe/0WuoX28MxaXe3LMmPb0wCgYIKoZIzj0EAwIwIDEeMBwGA1UEAwwVQ2FzYVJlZWwgVGVzdCBSb290IENBMB4XDTI2MTEwOTEzMzExM1oXDTM2MTEwNjEzMzExM1owIDEeMBwGA1UEAwwVQ2FzYVJlZWwgVGVzdCBSb290IENBMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEuNVUHYk7Eixz37E804PrcC5pCu03jDCJ0maWQfRgF7EyPRZ0n9NBmMM63iT5Y1kpY0Z8b5zhDdlczfn3eEFN+aMjMCEwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwIDSQAwRgIhALLwUnZbmkj/4E7d46Vcyuml2ffrhVHV4kqJoDm3oZKMAiEA1rkVOPjqmQVIX6MN51czEjB/UwaEHD14eu8QL7NQGPI=")
    static let good = certificate("MIIBojCCAUegAwIBAgIUEMNQhUkwenkzvC139c210dEZcJwwCgYIKoZIzj0EAwIwIDEeMBwGA1UEAwwVQ2FzYVJlZWwgVGVzdCBSb290IENBMB4XDTI2MTEwOTEzMzExM1oXDTI3MTEwOTEzMzExM1owJDEiMCAGA1UEAwwZYXBpLnRlc3QuY2FzYXJlZWwuZXhhbXBsZTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABIUttBNYbhPFmJvE9n5+1BcAFlW3moViqcvbifBRKziD5onQRD1WVPxqjHALe7iIjMaNmKa9K3ykqKA5H03d1K2jWzBZMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUFBwMBMCQGA1UdEQQdMBuCGWFwaS50ZXN0LmNhc2FyZWVsLmV4YW1wbGUwCgYIKoZIzj0EAwIDSQAwRgIhANFCfb36UGQdsnn6QBL2Gx5In6rMkfQgKzLXty2j2lvZAiEAuY6GFO1FBiW0zvq7xc0SKxQOWeoPo/IEbEwa80HLbDE=")
    static let other = certificate("MIIBoTCCAUegAwIBAgIUEMNQhUkwenkzvC139c210dEZcJ0wCgYIKoZIzj0EAwIwIDEeMBwGA1UEAwwVQ2FzYVJlZWwgVGVzdCBSb290IENBMB4XDTI2MTEwOTEzMzExM1oXDTI3MTEwOTEzMzExM1owJDEiMCAGA1UEAwwZYXBpLnRlc3QuY2FzYXJlZWwuZXhhbXBsZTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABGmzHDBsYCv3TR0/YqoLFpEHNl6bPN696zKHwbZ6KCCOYTll8Nk2oUm1abkY8jdsuVcDvwMeKcAdKxPi1tlP572jWzBZMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUFBwMBMCQGA1UdEQQdMBuCGWFwaS50ZXN0LmNhc2FyZWVsLmV4YW1wbGUwCgYIKoZIzj0EAwIDSAAwRQIhAIumVN2fzOwRW15TDApW1CiBp5YNqmVnMh4HD9e9A06iAiBtq9CsxG5bcE/syZSN+OeclE8+gUMvu23se3pz0qAoug==")
    static let shortLived = certificate("MIIBoDCCAUegAwIBAgIUEMNQhUkwenkzvC139c210dEZcJ4wCgYIKoZIzj0EAwIwIDEeMBwGA1UEAwwVQ2FzYVJlZWwgVGVzdCBSb290IENBMB4XDTI2MTEwOTEzMzExM1oXDTI2MTExMDEzMzExM1owJDEiMCAGA1UEAwwZYXBpLnRlc3QuY2FzYXJlZWwuZXhhbXBsZTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABM/0f3BPNdQ9f83mk45kldrdmXoN6+Mv3aY67RKu0rAclEoHBnBIu3xepyVTmHrBame1uQq45kbd9W6MbM10f+WjWzBZMAwGA1UdEwEB/wQCMAAwDgYDVR0PAQH/BAQDAgWgMBMGA1UdJQQMMAoGCCsGAQUFBwMBMCQGA1UdEQQdMBuCGWFwaS50ZXN0LmNhc2FyZWVsLmV4YW1wbGUwCgYIKoZIzj0EAwIDRwAwRAIgbnhPnpUv8Hx1c1ViLnuwmQoOhw/MMYiHOUFyFL7/g7cCIEBdmnWLgouOLkuVLKCkZzfwSeqwMVdPdfN4DcMBsPQD")

    private static func certificate(_ base64: String) -> SecCertificate {
        guard let data = Data(base64Encoded: base64), let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
            preconditionFailure("Invalid embedded test certificate")
        }
        return certificate
    }

    /// A server trust for `leaf` anchored only to the test CA, optionally evaluated at `date`.
    static func trust(for leaf: SecCertificate, anchored: Bool = true, at date: Date? = nil) -> SecTrust {
        var trust: SecTrust?
        SecTrustCreateWithCertificates([leaf, ca] as CFArray, SecPolicyCreateSSL(true, host as CFString), &trust)
        guard let trust else { preconditionFailure("Could not create trust") }
        if anchored {
            SecTrustSetAnchorCertificates(trust, [ca] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
        }
        if let date { SecTrustSetVerifyDate(trust, date as CFDate) }
        return trust
    }
}
