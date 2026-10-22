import Foundation

/// The camera's live page outline, steadied (ux-notes row 133, 04 §5.1 "Camera controls"). Each
/// reading Vision gives (about ten a second) is fed in; what comes out is the outline to draw:
///
/// - Only an outline cleanup could crop to counts (`PageCleanup.isPlausible`): convex, a fair share
///   of the frame, clear of its edges, shaped like a page seen at a modest angle.
/// - The last plausible outline is held for half a second when a reading has none, so a frame the
///   detector misses doesn't blink it away.
/// - Readings ease into each other (each moves the outline halfway to the new one), and a jump
///   (a corner moving more than `jumpDistance`) is taken only when the next reading agrees, so one
///   stray reading never throws the outline across the page.
/// - After two seconds with no plausible outline, `hint` says what to change: Move Closer when the
///   page found is small, More Light when the frame is dark, Flatten the Page when an outline is
///   found but isn't page-shaped, Fill the Frame when none is. A page that fills the frame (its
///   outline at the frame's edges) needs no hint: cleanup reads the frame as it is.
///
/// The camera only feeds it; a capture still finds its page at full size in `PageCleanup`.
public struct PageOutlineSmoother: Sendable {
    /// What to change when no page can be found.
    public enum Hint: String, Sendable, Equatable, CaseIterable {
        case moveCloser, moreLight, flattenThePage, fillTheFrame

        public var label: String {
            switch self {
            case .moveCloser: "Move closer"
            case .moreLight: "More light"
            case .flattenThePage: "Flatten the page"
            case .fillTheFrame: "Fill the frame"
            }
        }
    }

    /// How long the last outline stays when readings have none.
    public var hold: Duration = .milliseconds(500)
    /// How long without a plausible outline before a hint.
    public var hintDelay: Duration = .seconds(2)
    /// A corner moving further than this (a share of the frame) is a jump.
    public var jumpDistance = 0.06
    /// Two readings this close agree.
    public var agreeDistance = 0.03
    /// A frame darker than this mean luminance (0…1) asks for more light.
    public var darkLuminance = 0.18

    /// The outline to draw, nil for none.
    public private(set) var outline: PageQuad?

    private var lastPlausible: ContinuousClock.Instant?
    private var missingSince: ContinuousClock.Instant?
    /// A jump waiting for a second reading.
    private var pending: PageQuad?
    /// The last reading without a plausible outline: what Vision found (if anything) and how dark.
    private var lastRaw: PageQuad?
    private var lastLuminance: Double?

    public init() {}

    /// One reading: Vision's outline (nil for none), when it was read, the frame's width over its
    /// height, and its mean luminance when measured. Returns the outline to draw.
    @discardableResult
    public mutating func feed(_ raw: PageQuad?, at time: ContinuousClock.Instant, aspect: Double, luminance: Double? = nil) -> PageQuad? {
        guard let raw, PageCleanup.isPlausible(raw, aspect: aspect) else {
            lastRaw = raw
            lastLuminance = luminance
            if missingSince == nil { missingSince = time }
            pending = nil
            if let lastPlausible, time - lastPlausible >= hold { outline = nil }
            if lastPlausible == nil { outline = nil }
            return outline
        }
        lastPlausible = time
        missingSince = nil
        lastRaw = nil
        guard let shown = outline else {
            outline = raw
            return outline
        }
        if raw.distance(to: shown) > jumpDistance {
            // A jump: taken when the reading after it agrees, ignored otherwise.
            if let pending, raw.distance(to: pending) <= agreeDistance {
                outline = raw
                self.pending = nil
            } else {
                pending = raw
            }
        } else {
            pending = nil
            outline = Self.blend(shown, raw, 0.5)
        }
        return outline
    }

    /// What the pill says when no page has been found for `hintDelay`; nil while one is, or before.
    public func hint(at time: ContinuousClock.Instant) -> Hint? {
        guard outline == nil, let missingSince, time - missingSince >= hintDelay else { return nil }
        if let raw = lastRaw, raw.isConvex {
            if Self.fillsFrame(raw) { return nil }
            if raw.area() < PageCleanup.minimumPageArea { return .moveCloser }
        }
        if let lastLuminance, lastLuminance < darkLuminance { return .moreLight }
        return lastRaw == nil ? .fillTheFrame : .flattenThePage
    }

    /// The page runs to the frame's edges on every side: there is nothing to frame better.
    static func fillsFrame(_ quad: PageQuad) -> Bool {
        quad.area() >= 0.8 && quad.corners.allSatisfy { min($0.x, 1 - $0.x) < 0.04 && min($0.y, 1 - $0.y) < 0.04 }
    }

    /// `a` moved `share` of the way to `b`, corner by corner.
    static func blend(_ a: PageQuad, _ b: PageQuad, _ share: Double) -> PageQuad {
        func mix(_ p: PagePoint, _ q: PagePoint) -> PagePoint { PagePoint(x: p.x + (q.x - p.x) * share, y: p.y + (q.y - p.y) * share) }
        return PageQuad(topLeft: mix(a.topLeft, b.topLeft), topRight: mix(a.topRight, b.topRight),
                        bottomRight: mix(a.bottomRight, b.bottomRight), bottomLeft: mix(a.bottomLeft, b.bottomLeft))
    }
}
