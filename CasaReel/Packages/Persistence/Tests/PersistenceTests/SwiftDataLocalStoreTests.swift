import Domain
import Testing
@testable import Persistence

struct SwiftDataLocalStoreTests {
    @Test func conformsToDomainContract() {
        let service: any LocalStore = SwiftDataLocalStore()
        #expect(service is SwiftDataLocalStore)
    }
}
