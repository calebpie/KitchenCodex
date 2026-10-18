import Foundation
import Testing
@testable import Units

@Suite("Temperature conversion")
struct TemperatureTests {
    @Test(arguments: [
        (Rational(350), Rational(530, 3)),
        (Rational(212), Rational(100)),
        (Rational(32), Rational(0)),
        (Rational(0), Rational(-160, 9)),
        (Rational(475), Rational(2_215, 9)),
        (Rational(-40), Rational(-40)),
    ])
    func fahrenheitToCelsiusIsExact(fahrenheit: Rational, celsius: Rational) {
        let f = Temperature(fahrenheit, .fahrenheit)
        let c = f.converted(to: .celsius)
        #expect(c == Temperature(celsius, .celsius))
        #expect(c.converted(to: .fahrenheit) == f)
    }

    @Test(arguments: [
        (Rational(180), Rational(356)),
        (Rational(100), Rational(212)),
        (Rational(0), Rational(32)),
        (Rational(240), Rational(464)),
        (Rational(1, 2), Rational(329, 10)),
    ])
    func celsiusToFahrenheitIsExact(celsius: Rational, fahrenheit: Rational) {
        let c = Temperature(celsius, .celsius)
        let f = c.converted(to: .fahrenheit)
        #expect(f == Temperature(fahrenheit, .fahrenheit))
        #expect(f.converted(to: .celsius) == c)
    }

    @Test func sameScaleIsUnchanged() {
        let f = Temperature(350, .fahrenheit, fan: true)
        #expect(f.converted(to: .fahrenheit) == f)
        let gas = Temperature(Rational(11, 2), .gasMark)
        #expect(gas.converted(to: .gasMark) == gas, "an off-table mark is kept as written")
    }

    @Test(arguments: [
        (Rational(1, 4), 225, 110), (Rational(1, 2), 250, 120),
        (Rational(1), 275, 140), (Rational(2), 300, 150), (Rational(3), 325, 170),
        (Rational(4), 350, 180), (Rational(5), 375, 190), (Rational(6), 400, 200),
        (Rational(7), 425, 220), (Rational(8), 450, 230), (Rational(9), 475, 240),
        (Rational(10), 500, 260),
    ])
    func gasMarkTable(mark: Rational, fahrenheit: Int, celsius: Int) {
        let gas = Temperature(mark, .gasMark)
        #expect(gas.converted(to: .fahrenheit) == Temperature(Rational(fahrenheit), .fahrenheit))
        #expect(gas.converted(to: .celsius) == Temperature(Rational(celsius), .celsius))
        // The table values come straight back to the same mark.
        #expect(Temperature(Rational(fahrenheit), .fahrenheit).converted(to: .gasMark) == gas)
        #expect(Temperature(Rational(celsius), .celsius).converted(to: .gasMark) == gas)
    }

    @Test(arguments: [
        (Rational(335), Rational(3)),     // nearer 325 than 350
        (Rational(345), Rational(4)),
        (Rational(356), Rational(4)),     // 180°C exactly, as Fahrenheit
        (Rational(675, 2), Rational(4)),  // 337.5 is a midpoint: the hotter mark wins
        (Rational(464), Rational(9)),
        (Rational(100), Rational(1, 4)),  // below the table clamps to the coldest mark
        (Rational(600), Rational(10)),    // above it to the hottest
    ])
    func fahrenheitRoundsToNearestMark(fahrenheit: Rational, mark: Rational) {
        #expect(Temperature(fahrenheit, .fahrenheit).converted(to: .gasMark) == Temperature(mark, .gasMark))
    }

    @Test(arguments: [
        (Rational(176), Rational(4)),
        (Rational(175), Rational(4)),     // midpoint between 170 and 180 goes hotter
        (Rational(165), Rational(3)),     // 5 from 170, 15 from 150
        (Rational(210), Rational(7)),     // midpoint between 200 and 220 goes hotter
        (Rational(230), Rational(8)),
        (Rational(90), Rational(1, 4)),
        (Rational(300), Rational(10)),
    ])
    func celsiusRoundsToNearestMark(celsius: Rational, mark: Rational) {
        #expect(Temperature(celsius, .celsius).converted(to: .gasMark) == Temperature(mark, .gasMark))
    }

    @Test func offTableGasMarksSnapBeforeConverting() {
        #expect(Temperature(Rational(11, 2), .gasMark).converted(to: .fahrenheit).degrees == 400, "5½ snaps hotter, to 6")
        #expect(Temperature(Rational(53, 10), .gasMark).converted(to: .celsius).degrees == 190, "5.3 snaps to 5")
        #expect(Temperature(12, .gasMark).converted(to: .celsius).degrees == 260)
        #expect(Temperature(0, .gasMark).converted(to: .fahrenheit).degrees == 225)
    }

    @Test func fanFlagSurvivesConversion() {
        let fan = Temperature(220, .celsius, fan: true)
        #expect(fan.converted(to: .fahrenheit) == Temperature(428, .fahrenheit, fan: true))
        #expect(fan.converted(to: .gasMark) == Temperature(7, .gasMark, fan: true))
        #expect(Temperature(6, .gasMark, fan: true).converted(to: .celsius).fan)
        #expect(!Temperature(220, .celsius).converted(to: .fahrenheit).fan)
    }

    @Test func gasMarkIsAStableRoundTrip() {
        for mark in [Rational(1, 4), Rational(1, 2), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] as [Rational] {
            let gas = Temperature(mark, .gasMark)
            #expect(gas.converted(to: .fahrenheit).converted(to: .gasMark) == gas)
            #expect(gas.converted(to: .celsius).converted(to: .gasMark) == gas)
            #expect(gas.converted(to: .fahrenheit).converted(to: .celsius).converted(to: .gasMark) == gas)
        }
    }

    @Test func fahrenheitCelsiusRoundTripIsExactForAnyRational() {
        for numerator in stride(from: -400, through: 2_000, by: 37) {
            for denominator in [1, 2, 3, 7, 10] {
                let f = Temperature(Rational(numerator, denominator), .fahrenheit)
                #expect(f.converted(to: .celsius).converted(to: .fahrenheit) == f)
                let c = Temperature(Rational(numerator, denominator), .celsius)
                #expect(c.converted(to: .fahrenheit).converted(to: .celsius) == c)
            }
        }
    }

    @Test func codableAndHashable() throws {
        let original = Temperature(Rational(530, 3), .celsius, fan: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Temperature.self, from: data)
        #expect(decoded == original)
        #expect(Set([original, decoded]).count == 1)
        #expect(Temperature(180, .celsius) != Temperature(180, .celsius, fan: true))
        #expect(Temperature(4, .gasMark) != Temperature(4, .celsius))
    }
}
