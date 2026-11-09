import Domain
import Testing
@testable import Networking

struct URLSessionAPIClientTests {
    @Test func conformsToDomainContract() {
        let service: any APIClient = URLSessionAPIClient()
        #expect(service is URLSessionAPIClient)
    }
}
