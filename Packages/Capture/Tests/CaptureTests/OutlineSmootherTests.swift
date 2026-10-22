import Foundation
import Testing
@testable import Capture

/// The live outline's hold, easing, jumps and hints (ux-notes row 133), on made-up readings ten a
/// second.
@Suite("Live page outline")
struct OutlineSmootherTests {
    static let start = ContinuousClock.now

    static func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    /// A page-shaped outline from (x, y) to (x + width, y + height).
    static func page(x: Double, y: Double, width: Double = 0.6, height: Double = 0.7) -> PageQuad {
        PageQuad(topLeft: PagePoint(x: x, y: y), topRight: PagePoint(x: x + width, y: y),
                 bottomRight: PagePoint(x: x + width, y: y + height), bottomLeft: PagePoint(x: x, y: y + height))
    }

    @Test func holdsThroughAMissedReadingAndEasesBetweenReadings() throws {
        var smoother = PageOutlineSmoother()
        let first = Self.page(x: 0.2, y: 0.15)
        #expect(smoother.feed(first, at: Self.at(0), aspect: 0.75) == first)
        // Nothing found for 300 ms: the outline stays.
        #expect(smoother.feed(nil, at: Self.at(100), aspect: 0.75) == first)
        #expect(smoother.feed(nil, at: Self.at(400), aspect: 0.75) == first)
        // Past half a second: it goes.
        #expect(smoother.feed(nil, at: Self.at(600), aspect: 0.75) == nil)

        // A small move eases halfway.
        smoother.feed(first, at: Self.at(700), aspect: 0.75)
        smoother.feed(Self.page(x: 0.24, y: 0.15), at: Self.at(800), aspect: 0.75)
        let moved = try #require(smoother.outline)
        #expect(abs(moved.topLeft.x - 0.22) < 1e-9)
    }

    @Test func aJumpWaitsForASecondReading() {
        var smoother = PageOutlineSmoother()
        let here = Self.page(x: 0.2, y: 0.15)
        let there = Self.page(x: 0.35, y: 0.2, width: 0.5, height: 0.6)
        smoother.feed(here, at: Self.at(0), aspect: 0.75)
        // One reading far away is ignored.
        #expect(smoother.feed(there, at: Self.at(100), aspect: 0.75) == here)
        // Back where it was: still here.
        #expect(smoother.feed(here, at: Self.at(200), aspect: 0.75) == here)
        // Two readings in a row agree: the outline goes there.
        smoother.feed(there, at: Self.at(300), aspect: 0.75)
        #expect(smoother.feed(there, at: Self.at(400), aspect: 0.75) == there)
    }

    @Test func onlyAnOutlineCleanupWouldCropToIsDrawn() {
        var smoother = PageOutlineSmoother()
        // A sliver, a skewed shape, and one running off the frame are not pages.
        let sliver = Self.page(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
        let skewed = PageQuad(topLeft: PagePoint(x: 0.1, y: 0.1), topRight: PagePoint(x: 0.9, y: 0.5),
                              bottomRight: PagePoint(x: 0.9, y: 0.6), bottomLeft: PagePoint(x: 0.1, y: 0.9))
        let offFrame = Self.page(x: 0.0, y: 0.1, width: 0.8)
        for (index, quad) in [sliver, skewed, offFrame].enumerated() {
            #expect(smoother.feed(quad, at: Self.at(index * 100), aspect: 0.75) == nil)
        }
    }

    @Test func saysWhatToChangeAfterTwoSeconds() {
        func hint(after readings: [PageQuad?], luminance: Double = 0.5) -> PageOutlineSmoother.Hint? {
            var smoother = PageOutlineSmoother()
            for (index, quad) in readings.enumerated() {
                smoother.feed(quad, at: Self.at(index * 100), aspect: 0.75, luminance: luminance)
            }
            return smoother.hint(at: Self.at(readings.count * 100))
        }
        let small = Self.page(x: 0.4, y: 0.4, width: 0.2, height: 0.25)
        let curled = PageQuad(topLeft: PagePoint(x: 0.1, y: 0.1), topRight: PagePoint(x: 0.9, y: 0.4),
                              bottomRight: PagePoint(x: 0.9, y: 0.6), bottomLeft: PagePoint(x: 0.1, y: 0.9))
        let filling = Self.page(x: 0.01, y: 0.01, width: 0.98, height: 0.98)
        // Not yet two seconds: nothing said.
        #expect(hint(after: Array(repeating: nil, count: 10)) == nil)
        #expect(hint(after: Array(repeating: small, count: 21)) == .moveCloser)
        #expect(hint(after: Array(repeating: nil, count: 21), luminance: 0.08) == .moreLight)
        #expect(hint(after: Array(repeating: curled, count: 21)) == .flattenThePage)
        #expect(hint(after: Array(repeating: nil, count: 21)) == .fillTheFrame)
        #expect(hint(after: Array(repeating: filling, count: 21)) == nil)
        // A page found again ends the hint.
        var smoother = PageOutlineSmoother()
        for index in 0..<21 { smoother.feed(nil, at: Self.at(index * 100), aspect: 0.75) }
        smoother.feed(Self.page(x: 0.2, y: 0.15), at: Self.at(2_100), aspect: 0.75)
        #expect(smoother.hint(at: Self.at(2_200)) == nil)
    }
}
