import Testing
@testable import Units

@Suite("Rational arithmetic")
struct RationalArithmeticTests {
    @Test func integerLiterals() {
        let r: Rational = 3
        #expect(r == Rational(3, 1))
        #expect(Rational(1, 2) * 2 == 1)
    }

    @Test func subtractsAndDivides() {
        #expect(Rational(1, 2) - Rational(1, 3) == Rational(1, 6))
        #expect(Rational(3, 4) / Rational(3, 2) == Rational(1, 2))
        #expect(-Rational(2, 3) == Rational(-2, 3))
        #expect(Rational(-5, 4).magnitude == Rational(5, 4))
        #expect(Rational(3, 7).reciprocal == Rational(7, 3))
    }

    @Test(arguments: [
        (Rational(7, 4), 1), (Rational(-7, 4), -2), (Rational(3), 3), (Rational(-1, 3), -1), (Rational(0), 0),
    ])
    func floors(value: Rational, expected: Int) {
        #expect(value.floor == expected)
    }

    @Test(arguments: [
        (Rational(1, 2), 1), (Rational(3, 2), 2), (Rational(-1, 2), -1), (Rational(7, 5), 1), (Rational(8, 5), 2), (Rational(2), 2),
    ])
    func roundsToIntTiesAwayFromZero(value: Rational, expected: Int) {
        #expect(value.roundedToInt == expected)
    }

    @Test(arguments: [
        (Rational(7, 16), Rational(1, 4), Rational(1, 2)),
        (Rational(5, 16), Rational(1, 4), Rational(1, 4)),
        (Rational(1, 3), Rational(1, 8), Rational(3, 8)),
        (Rational(236_588, 1_000), Rational(5), Rational(235)),
        (Rational(-7, 16), Rational(1, 4), Rational(-1, 2)),
        (Rational(1, 16), Rational(1, 8), Rational(1, 8)),
    ])
    func roundsToMultiples(value: Rational, step: Rational, expected: Rational) {
        #expect(value.rounded(toNearestMultipleOf: step) == expected)
    }

    @Test func detectsMultiples() {
        #expect(Rational(3, 4).isMultiple(of: Rational(1, 4)))
        #expect(Rational(2, 3).isMultiple(of: Rational(1, 3)))
        #expect(!Rational(3, 8).isMultiple(of: Rational(1, 4)))
        #expect(Rational(0).isMultiple(of: Rational(1, 3)))
    }

    @Test func compoundAssignment() {
        var r = Rational(1, 2)
        r += Rational(1, 4)
        r *= 2
        r -= Rational(1, 2)
        r /= 2
        #expect(r == Rational(1, 2))
    }
}
