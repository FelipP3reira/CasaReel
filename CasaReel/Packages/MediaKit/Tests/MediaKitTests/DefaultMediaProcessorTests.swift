import Domain
import Testing
@testable import MediaKit

struct DefaultMediaProcessorTests {
    @Test func conformsToDomainContract() {
        let service: any MediaProcessor = DefaultMediaProcessor()
        #expect(service is DefaultMediaProcessor)
    }
}
