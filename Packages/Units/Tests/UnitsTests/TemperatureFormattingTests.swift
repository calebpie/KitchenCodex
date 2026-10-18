import Foundation
import Testing
@testable import Units

@Suite("Temperature formatting")
struct TemperatureFormattingTests {
    @Test(arguments: [
        (Temperature(350, .fahrenheit), "350°F", "350 degrees Fahrenheit"),
        (Temperature(180, .celsius), "180°C", "180 degrees Celsius"),
        (Temperature(160, .celsius, fan: true), "160°C fan", "160 degrees Celsius (fan)"),
        (Temperature(325, .fahrenheit, fan: true), "325°F fan", "325 degrees Fahrenheit (fan)"),
        (Temperature(6, .gasMark), "gas 6", "gas mark 6"),
        (Temperature(Rational(1, 2), .gasMark), "gas ½", "gas mark ½"),
        (Temperature(Rational(1, 4), .gasMark), "gas ¼", "gas mark ¼"),
        (Temperature(Rational(13, 2), .gasMark), "gas 6½", "gas mark 6½"),
        (Temperature(Rational(530, 3), .celsius), "176.7°C", "176.7 degrees Celsius"),
        (Temperature(Rational(329, 10), .fahrenheit), "32.9°F", "32.9 degrees Fahrenheit"),
        (Temperature(-18, .celsius), "-18°C", "-18 degrees Celsius"),
        (Temperature(0, .fahrenheit), "0°F", "0 degrees Fahrenheit"),
    ])
    func ownScale(temperature: Temperature, abbreviated: String, full: String) {
        #expect(temperature.formatted() == abbreviated)
        #expect(temperature.formatted(style: .abbreviated) == abbreviated)
        #expect(temperature.formatted(style: .full) == full)
        #expect(temperature.description == abbreviated)
        #expect(temperature.formatted(in: temperature.scale) == abbreviated, "own scale shows the value as written")
    }

    @Test(arguments: [
        (Temperature(350, .fahrenheit), TemperatureScale.celsius, "175°C"),      // 176⅔ rounds to the nearest 5
        (Temperature(425, .fahrenheit), .celsius, "220°C"),                      // 218⅓
        (Temperature(400, .fahrenheit), .celsius, "205°C"),                      // 204.4
        (Temperature(180, .celsius), .fahrenheit, "355°F"),                      // 356
        (Temperature(200, .celsius), .fahrenheit, "390°F"),                      // 392
        (Temperature(240, .celsius), .fahrenheit, "465°F"),                      // 464
        (Temperature(63, .celsius), .fahrenheit, "145°F"),                       // 145.4, a probe temperature
        (Temperature(Rational(1325, 10), .fahrenheit), .celsius, "55°C"),        // 56.4
        (Temperature(4, .gasMark), .fahrenheit, "350°F"),
        (Temperature(4, .gasMark), .celsius, "180°C"),
        (Temperature(Rational(1, 2), .gasMark), .fahrenheit, "250°F"),
        (Temperature(180, .celsius), .gasMark, "gas 4"),
        (Temperature(356, .fahrenheit), .gasMark, "gas 4"),
        (Temperature(475, .fahrenheit), .gasMark, "gas 9"),
        (Temperature(220, .celsius, fan: true), .fahrenheit, "430°F fan"),       // 428
        (Temperature(160, .celsius, fan: true), .gasMark, "gas 3 fan"),
    ])
    func convertedForDisplay(temperature: Temperature, scale: TemperatureScale, text: String) {
        #expect(temperature.formatted(in: scale) == text)
        #expect(temperature.displayed(in: scale).formatted() == text)
    }

    @Test func fullStyleAfterConversion() {
        #expect(Temperature(180, .celsius).formatted(in: .fahrenheit, style: .full) == "355 degrees Fahrenheit")
        #expect(Temperature(6, .gasMark).formatted(in: .celsius, style: .full) == "200 degrees Celsius")
        #expect(Temperature(350, .fahrenheit).formatted(in: .gasMark, style: .full) == "gas mark 4")
    }

    @Test func displayedRoundsOnlyWhenConverting() {
        let awkward = Temperature(Rational(530, 3), .celsius)
        #expect(awkward.displayed(in: .celsius) == awkward)
        #expect(awkward.displayed(in: .fahrenheit) == Temperature(350, .fahrenheit))
        let odd = Temperature(177, .celsius)
        #expect(odd.displayed(in: .celsius).degrees == 177, "a recipe's own 177°C is not rounded")
        #expect(odd.displayed(in: .fahrenheit).degrees == 350, "350.6 rounds to 350")
        #expect(Temperature.displayRoundingStep == 5)
    }

    @Test func displayedIsIdempotentInTheTargetScale() {
        for degrees in stride(from: 100, through: 500, by: 7) {
            for scale in TemperatureScale.allCases {
                let shown = Temperature(Rational(degrees), .fahrenheit).displayed(in: scale)
                #expect(shown.scale == scale)
                #expect(shown.displayed(in: scale) == shown)
                // Only a converted value is rounded; Fahrenheit shown in Fahrenheit stays as written.
                if scale == .celsius { #expect(shown.degrees.isMultiple(of: 5)) }
                if scale == .fahrenheit { #expect(shown.degrees == Rational(degrees)) }
            }
        }
    }

    @Test func parsedTemperaturePrefersWhatWasWritten() {
        let british = TemperatureParser.parse("240C/fan 220C/gas 9")!
        #expect(british.formatted(in: .celsius) == "240°C", "the conventional value, not the fan one")
        #expect(british.formatted(in: .gasMark) == "gas 9")
        #expect(british.formatted(in: .fahrenheit) == "475°F", "the gas mark gives the chart value, not 465°F")
        #expect(british.originalText == "240C/fan 220C/gas 9")

        let mixed = TemperatureParser.parse("200°C (180°C fan), gas 6, 400°F")!
        #expect(mixed.formatted(in: .fahrenheit) == "400°F")
        #expect(mixed.formatted(in: .celsius) == "200°C")
        #expect(mixed.formatted(in: .gasMark, style: .full) == "gas mark 6")

        let celsiusOnly = TemperatureParser.parse("190°C")!
        #expect(celsiusOnly.formatted(in: .fahrenheit) == "375°F")
        #expect(celsiusOnly.formatted(in: .gasMark) == "gas 5")

        let fanOnly = TemperatureParser.parse("fan 160°C")!
        #expect(fanOnly.formatted(in: .celsius) == "160°C fan", "a fan value is shown, tagged, when it is all there is")
        #expect(fanOnly.formatted(in: .fahrenheit) == "320°F fan")
        #expect(fanOnly.displayed(in: .fahrenheit).fan)

        let fanAndGas = TemperatureParser.parse("fan 160°C/gas 4")!
        #expect(fanAndGas.formatted(in: .celsius) == "180°C", "the gas mark stands in for the conventional oven")
        #expect(fanAndGas.formatted(in: .fahrenheit) == "350°F")

        let words = TemperatureParser.parse("moderate oven")!
        #expect(words.formatted(in: .fahrenheit) == "350°F")
        #expect(words.formatted(in: .celsius) == "180°C")
        #expect(words.formatted(in: .gasMark) == "gas 4")
        #expect(words.originalText == "moderate oven")
    }
}
