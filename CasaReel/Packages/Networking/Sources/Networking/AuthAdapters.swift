import Domain
import Foundation
import SecurityKit

/// `/auth/refresh` for `TokenManager`. Must use a client without tokens, or a 401 would recurse.
public struct APITokenRefresher: TokenRefreshing {
    private let client: any APIClient

    public init(unauthenticatedClient: any APIClient) {
        client = unauthenticatedClient
    }

    public func refresh(using refreshToken: String) async throws(TokenRefreshError) -> TokenPair {
        do {
            return try await client.send(API.refresh(refreshToken: refreshToken))
        } catch {
            // An invalid or reused refresh token is as final as an explicit revocation.
            switch error.code {
            case .sessionRevoked, .unauthorized, .forbidden: throw .sessionRevoked
            default: throw .transient
            }
        }
    }
}

/// `/attest/challenge` and `/attest/register` for `AppAttestClient`. Uses a client without App Attest.
public struct APIAttestServer: AttestServerAPI {
    private let client: any APIClient

    public init(client: any APIClient) {
        self.client = client
    }

    public func challenge() async throws -> String {
        try await client.send(API.attestChallenge()).challenge
    }

    public func register(keyId: String, attestationObject: Data, challenge: String) async throws {
        _ = try await client.send(API.attestRegister(keyId: keyId, attestationObject: attestationObject, challenge: challenge))
    }
}
