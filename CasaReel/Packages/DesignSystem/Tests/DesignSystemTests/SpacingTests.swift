import Testing
@testable import DesignSystem

struct SpacingTests {
    @Test func scaleIsAscending() {
        #expect(Spacing.small < Spacing.medium)
        #expect(Spacing.medium < Spacing.large)
    }
}
