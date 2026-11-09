import Domain
import Testing
@testable import VideoEngine

struct AVFoundationVideoRendererTests {
    @Test func conformsToDomainContract() {
        let service: any VideoRenderer = AVFoundationVideoRenderer()
        #expect(service is AVFoundationVideoRenderer)
    }
}
