import Domain
import Testing
@testable import SecurityKit

struct KeychainSecureStoreTests {
    @Test func conformsToDomainContract() {
        let service: any SecureStore = KeychainSecureStore()
        #expect(service is KeychainSecureStore)
    }
}
