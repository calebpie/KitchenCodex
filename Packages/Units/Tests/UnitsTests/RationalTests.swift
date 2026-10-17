import Testing
@testable import Units

@Suite("Rational")
struct RationalTests {
    @Test func normalizesToLowestTerms() {
        let r = Rational(6, 8)
        #expect(r.numerator == 3)
        #expect(r.denominator == 4)
    }

    @Test func normalizesSignToNumerator() {
        let r = Rational(1, -2)
        #expect(r.numerator == -1)
        #expect(r.denominator == 2)
    }

    @Test(arguments: [
        (Rational(1, 3), Rational(3, 2), Rational(1, 2)),
        (Rational(3, 4), Rational(2), Rational(3, 2)),
        (Rational(2), Rational(1, 2), Rational(1)),
    ])
    func multiplies(a: Rational, b: Rational, expected: Rational) {
        #expect(a * b == expected)
    }

    @Test func addsWithUnlikeDenominators() {
        #expect(Rational(1, 3) + Rational(1, 6) == Rational(1, 2))
    }

    @Test(arguments: [
        (Rational(7, 4), "1 3/4"),
        (Rational(1, 2), "1/2"),
        (Rational(3), "3"),
        (Rational(0), "0"),
    ])
    func describesAsMixedNumber(value: Rational, text: String) {
        #expect(value.description == text)
    }

    @Test func scalesQuantityExactly() {
        let flour = Quantity(Rational(1, 3), .cup)
        let scaled = flour.scaled(by: Rational(3, 2))
        #expect(scaled.value == Rational(1, 2))
        #expect(scaled.unit == .cup)
    }
}
