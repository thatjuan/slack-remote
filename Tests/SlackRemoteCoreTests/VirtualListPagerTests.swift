import Foundation
import SlackRemoteCore
import Testing

@MainActor
struct VirtualListPagerTests {
    @Test func stopsAtBoundaryAndKeepsOverlappingPagesInOrder() throws {
        let fixture = PagingFixture([[6, 7, 8, 8], [3, 5, 6], [1, 2, 3, 4, 5]], direction: .towardStart)
        let paged = try VirtualListPager.collect(direction: .towardStart,
            bounds: .init(maxItems: 20, maxPages: 10, deadline: Date().addingTimeInterval(5)),
            rendered: fixture.rendered, reachedBoundary: { $0 == 2 }, atEnd: { false })
        #expect(paged.items == [2, 3, 4, 5, 6, 7, 8])
        #expect(paged.stopReason == .boundary)
        #expect(paged.pages == 3)
        #expect(paged.complete)
    }

    @Test func itemLimitKeepsNewestItemsWhenPagingTowardStart() throws {
        let fixture = PagingFixture([[1, 2, 3]], direction: .towardStart)
        let paged = try VirtualListPager.collect(direction: .towardStart,
            bounds: .init(maxItems: 2, maxPages: 10, deadline: .distantFuture),
            rendered: fixture.rendered, reachedBoundary: { _ in false }, atEnd: { true })
        #expect(paged.items == [2, 3])
        #expect(paged.stopReason == .limit)
        #expect(fixture.moves == 0)
    }

    @Test func pageLimitCountsInitialSnapshot() throws {
        let fixture = PagingFixture([[1, 2], [3, 4]], direction: .towardEnd)
        let paged = try VirtualListPager.collect(direction: .towardEnd,
            bounds: .init(maxItems: 20, maxPages: 2, deadline: .distantFuture),
            rendered: fixture.rendered, reachedBoundary: { _ in false }, atEnd: { false })
        #expect(paged.items == [1, 2, 3, 4])
        #expect(paged.pages == 2)
        #expect(paged.stopReason == .limit)
        #expect(fixture.moves == 1)
        #expect(!paged.complete)
    }

    @Test func endMarkerTakesPrecedenceOverPageLimit() throws {
        let fixture = PagingFixture([[1], [1, 2]], direction: .towardEnd)
        let paged = try VirtualListPager.collect(direction: .towardEnd,
            bounds: .init(maxItems: 20, maxPages: 2, deadline: .distantFuture),
            rendered: fixture.rendered, reachedBoundary: { _ in false }, atEnd: { fixture.index == 1 })
        #expect(paged.items == [1, 2])
        #expect(paged.stopReason == .endOfList)
        #expect(paged.complete)
    }

    @Test func threeScrollsWithoutNewKeysStall() throws {
        let fixture = PagingFixture([[3]], direction: .towardEnd)
        let paged = try VirtualListPager.collect(direction: .towardEnd,
            bounds: .init(maxItems: 20, maxPages: 20, deadline: Date().addingTimeInterval(10)),
            rendered: fixture.rendered, reachedBoundary: { _ in false }, atEnd: { false })
        #expect(paged.items == [3])
        #expect(paged.stopReason == .stalled)
        #expect(paged.pages == 4)
        #expect(fixture.moves == 3)
    }

    @Test func deadlinePreventsAnotherScroll() throws {
        let fixture = PagingFixture([[3]], direction: .towardEnd)
        let paged = try VirtualListPager.collect(direction: .towardEnd,
            bounds: .init(maxItems: 20, maxPages: 4, deadline: .distantPast),
            rendered: fixture.rendered, reachedBoundary: { _ in false }, atEnd: { false })
        #expect(paged.items == [3])
        #expect(paged.stopReason == .deadline)
        #expect(fixture.moves == 0)
    }
}
