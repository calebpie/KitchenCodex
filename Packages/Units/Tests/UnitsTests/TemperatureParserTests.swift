import Foundation
import Testing
@testable import Units

@Suite("Temperature parser")
struct TemperatureParserTests {
    @Test(arguments: [
        ("350°F", Temperature(350, .fahrenheit)),
        ("350 F", Temperature(350, .fahrenheit)),
        ("350F", Temperature(350, .fahrenheit)),
        ("350 °F", Temperature(350, .fahrenheit)),
        ("350 degrees F", Temperature(350, .fahrenheit)),
        ("350 degrees F.", Temperature(350, .fahrenheit)),
        ("350 degree F", Temperature(350, .fahrenheit)),
        ("350 deg F", Temperature(350, .fahrenheit)),
        ("350 deg. F", Temperature(350, .fahrenheit)),
        ("350 degrees Fahrenheit", Temperature(350, .fahrenheit)),
        ("350 Degrees fahrenheit", Temperature(350, .fahrenheit)),
        ("350°f", Temperature(350, .fahrenheit)),
        ("350ºF", Temperature(350, .fahrenheit)),
        ("350˚F", Temperature(350, .fahrenheit)),
        ("350℉", Temperature(350, .fahrenheit)),
        ("  350°F  ", Temperature(350, .fahrenheit)),
        ("(350°F)", Temperature(350, .fahrenheit)),
        ("350°F.", Temperature(350, .fahrenheit)),
        ("180 C", Temperature(180, .celsius)),
        ("180°C", Temperature(180, .celsius)),
        ("180C", Temperature(180, .celsius)),
        ("180 c", Temperature(180, .celsius)),
        ("180 ° C", Temperature(180, .celsius)),
        ("180 degrees C", Temperature(180, .celsius)),
        ("180 degrees Celsius", Temperature(180, .celsius)),
        ("180 degrees centigrade", Temperature(180, .celsius)),
        ("180℃", Temperature(180, .celsius)),
        ("375º degrees Fahrenheit", Temperature(375, .fahrenheit)),
        ("375° degrees F", Temperature(375, .fahrenheit)),
        ("375° degree F", Temperature(375, .fahrenheit)),
        ("375˚ degrees F.", Temperature(375, .fahrenheit)),
        ("375 ° degrees Fahrenheit", Temperature(375, .fahrenheit)),
        ("375°degrees F", Temperature(375, .fahrenheit)),
        ("375º deg. F", Temperature(375, .fahrenheit)),
        ("190º degrees Celsius", Temperature(190, .celsius)),
        ("190° degrees C", Temperature(190, .celsius)),
        ("190º Degrees centigrade", Temperature(190, .celsius)),
        ("375° degrees Fahrenheit", Temperature(375, .fahrenheit)),
        ("375˚ degrees F", Temperature(375, .fahrenheit)),
        ("375º degree Fahrenheit", Temperature(375, .fahrenheit)),
        ("375˚ degree F", Temperature(375, .fahrenheit)),
        ("375º degrees C", Temperature(375, .celsius)),
        ("375° degrees Celsius", Temperature(375, .celsius)),
        ("375˚ degrees Celsius", Temperature(375, .celsius)),
        ("190˚ degree C", Temperature(190, .celsius)),
        ("190º degree Celsius", Temperature(190, .celsius)),
        ("190° degree C", Temperature(190, .celsius)),
        ("176.5°C", Temperature(Rational(353, 2), .celsius)),
        ("62.5°C", Temperature(Rational(125, 2), .celsius)),
        ("5°C", Temperature(5, .celsius)),
        ("40°F", Temperature(40, .fahrenheit)),
        ("gas mark 6", Temperature(6, .gasMark)),
        ("Gas Mark 6", Temperature(6, .gasMark)),
        ("gas 9", Temperature(9, .gasMark)),
        ("Gas 4", Temperature(4, .gasMark)),
        ("gas mk 4", Temperature(4, .gasMark)),
        ("gas mk. 4", Temperature(4, .gasMark)),
        ("gasmark 3", Temperature(3, .gasMark)),
        ("gas mark ½", Temperature(Rational(1, 2), .gasMark)),
        ("gas mark 1/2", Temperature(Rational(1, 2), .gasMark)),
        ("gas ¼", Temperature(Rational(1, 4), .gasMark)),
        ("gas mark 6½", Temperature(Rational(13, 2), .gasMark)),
        ("gas mark 6 1/2", Temperature(Rational(13, 2), .gasMark)),
        ("gas mark 6.5", Temperature(Rational(13, 2), .gasMark)),
        ("very cool oven", Temperature(Rational(1, 2), .gasMark)),
        ("very slow oven", Temperature(Rational(1, 2), .gasMark)),
        ("cool oven", Temperature(1, .gasMark)),
        ("slow oven", Temperature(2, .gasMark)),
        ("moderately slow oven", Temperature(3, .gasMark)),
        ("moderate oven", Temperature(4, .gasMark)),
        ("Moderate Oven", Temperature(4, .gasMark)),
        ("medium oven", Temperature(4, .gasMark)),
        ("moderately hot oven", Temperature(5, .gasMark)),
        ("fairly hot oven", Temperature(6, .gasMark)),
        ("medium hot oven", Temperature(6, .gasMark)),
        ("hot oven", Temperature(7, .gasMark)),
        ("very hot oven", Temperature(9, .gasMark)),
        ("very  hot   oven", Temperature(9, .gasMark)),
    ])
    func parsesSingleForms(text: String, temperature: Temperature) {
        let parsed = TemperatureParser.parse(text)
        #expect(parsed?.alternatives == [temperature])
        #expect(parsed?.primary == temperature)
        #expect(TemperatureParser().parse(text)?.primary == temperature)
        #expect(Temperature(parsing: text) == temperature)
    }

    @Test(arguments: [
        ("fan 220C", Temperature(220, .celsius, fan: true)),
        ("Fan 220°C", Temperature(220, .celsius, fan: true)),
        ("fan oven 160°C", Temperature(160, .celsius, fan: true)),
        ("fan-assisted 170°C", Temperature(170, .celsius, fan: true)),
        ("fan forced 160C", Temperature(160, .celsius, fan: true)),
        ("fan: 160°C", Temperature(160, .celsius, fan: true)),
        ("160°C fan", Temperature(160, .celsius, fan: true)),
        ("160C Fan", Temperature(160, .celsius, fan: true)),
        ("160°C fan oven", Temperature(160, .celsius, fan: true)),
        ("160°C fan-forced", Temperature(160, .celsius, fan: true)),
        ("160°C (fan)", Temperature(160, .celsius, fan: true)),
        ("160°C ( fan )", Temperature(160, .celsius, fan: true)),
        ("325°F convection", Temperature(325, .fahrenheit, fan: true)),
        ("convection 325°F", Temperature(325, .fahrenheit, fan: true)),
        ("160° degrees C fan", Temperature(160, .celsius, fan: true)),
        ("convection 375º degrees F", Temperature(375, .fahrenheit, fan: true)),
    ])
    func tagsFanOvenValues(text: String, temperature: Temperature) {
        let parsed = TemperatureParser.parse(text)
        #expect(parsed?.alternatives == [temperature])
        #expect(parsed?.primary.fan == true)
        #expect(parsed?.originalText == text)
    }

    @Test func fanIsOnlyTaggedWhenTheWordIsThere() {
        #expect(TemperatureParser.parse("220C")?.primary.fan == false)
        #expect(TemperatureParser.parse("gas 6")?.primary.fan == false)
        #expect(TemperatureParser.parse("hot oven")?.primary.fan == false)
        #expect(TemperatureParser.parse("220°C fantastic") == nil, "a word that begins with fan is not the fan tag")
    }

    @Test(arguments: [
        ("240C/fan 220C/gas 9", [
            Temperature(240, .celsius), Temperature(220, .celsius, fan: true), Temperature(9, .gasMark),
        ]),
        ("200°C (180°C fan), gas 6, 400°F", [
            Temperature(200, .celsius), Temperature(180, .celsius, fan: true), Temperature(6, .gasMark), Temperature(400, .fahrenheit),
        ]),
        ("350°F/180°C/gas 4", [Temperature(350, .fahrenheit), Temperature(180, .celsius), Temperature(4, .gasMark)]),
        ("350°F (180°C)", [Temperature(350, .fahrenheit), Temperature(180, .celsius)]),
        ("180°C or 350°F", [Temperature(180, .celsius), Temperature(350, .fahrenheit)]),
        ("180°C and gas 4", [Temperature(180, .celsius), Temperature(4, .gasMark)]),
        ("190C, 375F, Gas 5", [Temperature(190, .celsius), Temperature(375, .fahrenheit), Temperature(5, .gasMark)]),
        ("Gas Mark 4 (180°C/350°F)", [Temperature(4, .gasMark), Temperature(180, .celsius), Temperature(350, .fahrenheit)]),
        ("moderate oven (180°C/350°F/gas 4)", [
            Temperature(4, .gasMark), Temperature(180, .celsius), Temperature(350, .fahrenheit), Temperature(4, .gasMark),
        ]),
        ("160°C fan/180°C/gas 4", [Temperature(160, .celsius, fan: true), Temperature(180, .celsius), Temperature(4, .gasMark)]),
        ("180°C | 160°C fan | gas 4", [Temperature(180, .celsius), Temperature(160, .celsius, fan: true), Temperature(4, .gasMark)]),
        ("220°C – 425°F", [Temperature(220, .celsius), Temperature(425, .fahrenheit)]),
        ("200°C/400°F/Gas 6 (fan 180°C)", [
            Temperature(200, .celsius), Temperature(400, .fahrenheit), Temperature(6, .gasMark), Temperature(180, .celsius, fan: true),
        ]),
        ("375º degrees Fahrenheit (190º degrees Celsius)", [Temperature(375, .fahrenheit), Temperature(190, .celsius)]),
        ("375° degrees F / 190° degrees C / gas 5", [Temperature(375, .fahrenheit), Temperature(190, .celsius), Temperature(5, .gasMark)]),
    ] as [(String, [Temperature])])
    func keepsEveryAlternativeInOrder(text: String, alternatives: [Temperature]) {
        let parsed = TemperatureParser.parse(text)
        #expect(parsed?.alternatives == alternatives)
        #expect(parsed?.originalText == text)
    }

    @Test(arguments: [
        "", " ", "350", "350°", "350 degrees", "180 degrees for 20 minutes", "2 C flour", "2 c sugar",
        "1 F", "9 C", "gas", "gas stove", "gas burner", "mark 6", "oven", "warm oven", "a hot pan",
        "hot", "moderate", "350°F for 20 minutes", "Bake at 350°F", "180°C then 200°C", "tbsp", "°F",
        "350 Fun", "180 Cups", "180 Celsiuss", "fan", "fan 6", "hotter oven", "coolest oven",
        "180° degrees", "350º degrees", "350° degrees for 20 minutes", "375° degrees Fun",
        "º", "ºF", "º F", "º degrees Fahrenheit", "˚ degrees C", "° degree Celsius", "degrees º F",
    ])
    func rejectsWhatIsNotAWholeTemperature(text: String) {
        #expect(TemperatureParser.parse(text) == nil)
        #expect(Temperature(parsing: text) == nil)
    }

    @Test func bareLettersNeedTwoDigits() {
        #expect(TemperatureParser.parse("10 C")?.primary == Temperature(10, .celsius))
        #expect(TemperatureParser.parse("9 C") == nil)
        #expect(TemperatureParser.parse("9°C")?.primary == Temperature(9, .celsius), "a degree sign is enough")
        #expect(TemperatureParser.parse("2 degrees C")?.primary == Temperature(2, .celsius))
        #expect(TemperatureParser.parse("2 celsius")?.primary == Temperature(2, .celsius))
        #expect(TemperatureParser.parse("5 F") == nil)
    }

    // MARK: - In a sentence

    @Test func findsOneMentionWithItsRange() {
        let text = "Preheat the oven to 350°F and grease a pan."
        let mentions = TemperatureParser.mentions(in: text)
        #expect(mentions.count == 1)
        let mention = try! #require(mentions.first)
        #expect(text[mention.range] == "350°F")
        #expect(mention.originalText == "350°F")
        #expect(mention.temperature.alternatives == [Temperature(350, .fahrenheit)])
        #expect(TemperatureParser().mentions(in: text) == mentions)
    }

    @Test func findsADoubledMarkerAsOneRun() {
        let text = "Preheat the oven to 375º degrees Fahrenheit and butter a 9 by 13 inch dish."
        let mentions = TemperatureParser.mentions(in: text)
        #expect(mentions.count == 1)
        let mention = try! #require(mentions.first)
        #expect(text[mention.range] == "375º degrees Fahrenheit")
        #expect(mention.originalText == "375º degrees Fahrenheit")
        #expect(mention.temperature.alternatives == [Temperature(375, .fahrenheit)])
        #expect(mention.temperature.formatted(in: .fahrenheit) == "375°F")
        #expect(mention.temperature.formatted(in: .celsius) == "190°C")
        var rendered = text
        rendered.replaceSubrange(mention.range, with: "[\(mention.temperature.formatted(in: .celsius))]")
        #expect(rendered == "Preheat the oven to [190°C] and butter a 9 by 13 inch dish.")
    }

    @Test func doubledMarkerAlternativesFormOneMention() {
        let text = "Bake at 375º degrees Fahrenheit (190º degrees Celsius) for 45 minutes, then rest at 70° degrees F."
        let mentions = TemperatureParser.mentions(in: text)
        #expect(mentions.map { text[$0.range] } == ["375º degrees Fahrenheit (190º degrees Celsius)", "70° degrees F"])
        let first = try! #require(mentions.first)
        #expect(first.originalText == "375º degrees Fahrenheit (190º degrees Celsius)")
        #expect(first.temperature.alternatives == [Temperature(375, .fahrenheit), Temperature(190, .celsius)])
        #expect(first.temperature.formatted(in: .celsius) == "190°C", "the written Celsius value, not a conversion")
        #expect(first.temperature.formatted(in: .fahrenheit) == "375°F")
        #expect(mentions.last?.temperature.primary == Temperature(70, .fahrenheit))
    }

    @Test(arguments: [
        ("Bake at 375º degrees Fahrenheit until set.", "375º degrees Fahrenheit", Temperature(375, .fahrenheit)),
        ("Bake at 375° degrees Fahrenheit until set.", "375° degrees Fahrenheit", Temperature(375, .fahrenheit)),
        ("Bake at 375˚ degrees F until set.", "375˚ degrees F", Temperature(375, .fahrenheit)),
        ("Bake at 375º degree F until set.", "375º degree F", Temperature(375, .fahrenheit)),
        ("Roast at 190º degrees Celsius for an hour.", "190º degrees Celsius", Temperature(190, .celsius)),
        ("Roast at 190° degree Celsius for an hour.", "190° degree Celsius", Temperature(190, .celsius)),
        ("Roast at 190˚ degrees C for an hour.", "190˚ degrees C", Temperature(190, .celsius)),
    ] as [(String, String, Temperature)])
    func doubledMarkerSpansTheWholeMention(text: String, span: String, temperature: Temperature) {
        let mentions = TemperatureParser.mentions(in: text)
        #expect(mentions.count == 1)
        #expect(mentions.map { String(text[$0.range]) } == [span])
        #expect(mentions.first?.originalText == span)
        #expect(mentions.first?.temperature.alternatives == [temperature])
    }

    @Test func aLoneDegreeSignReadsNothing() {
        for text in [
            "º", "ºF", "˚C", "º degrees Fahrenheit", "˚ degrees C",
            "Set the oven to º degrees Fahrenheit.",
            "Turn the dial past ºF and wait.",
            "Preheat to ˚ degrees C, then bake.",
        ] {
            #expect(TemperatureParser.parse(text) == nil, Comment(rawValue: text))
            #expect(TemperatureParser.mentions(in: text).isEmpty, Comment(rawValue: text))
        }
    }

    @Test func findsBritishCombinedFormInASentence() {
        let text = "Heat the oven to 240C/fan 220C/gas 9 and line a tray."
        let mentions = TemperatureParser.mentions(in: text)
        #expect(mentions.count == 1)
        #expect(mentions.first.map { text[$0.range] } == "240C/fan 220C/gas 9")
        #expect(mentions.first?.temperature.alternatives == [
            Temperature(240, .celsius), Temperature(220, .celsius, fan: true), Temperature(9, .gasMark),
        ])
    }

    @Test func includesTheClosingParenthesisItOpened() {
        let text = "Bake at 180°C (350°F) for 25 minutes."
        let mentions = TemperatureParser.mentions(in: text)
        #expect(mentions.map { text[$0.range] } == ["180°C (350°F)"])
        #expect(mentions.first?.temperature.alternatives == [Temperature(180, .celsius), Temperature(350, .fahrenheit)])

        let reversed = "Bake in a moderate oven (gas 4) until golden."
        #expect(TemperatureParser.mentions(in: reversed).map { reversed[$0.range] } == ["moderate oven (gas 4)"])

        let wrapped = "Set the oven (200°C fan) now."
        #expect(TemperatureParser.mentions(in: wrapped).map { wrapped[$0.range] } == ["200°C fan"], "a parenthesis the mention did not open stays outside")
    }

    @Test func separatesMentionsThatAreNotAlternatives() {
        let text = "Roast at 220°C for 20 minutes, then turn the oven down to 180°C (350°F) and cook for an hour; rest until the probe reads 63°C."
        let mentions = TemperatureParser.mentions(in: text)
        #expect(mentions.map { text[$0.range] } == ["220°C", "180°C (350°F)", "63°C"])
        #expect(mentions.map(\.temperature.alternatives.count) == [1, 2, 1])
        #expect(mentions[2].temperature.primary == Temperature(63, .celsius))
        // Ranges are in order and do not overlap.
        for (earlier, later) in zip(mentions, mentions.dropFirst()) {
            #expect(earlier.range.upperBound <= later.range.lowerBound)
        }
    }

    @Test func mentionsOfEveryKindInOneSentence() {
        let text = "Start in a very hot oven, drop to gas mark 4, finish at 160 degrees C fan or 325°F."
        let mentions = TemperatureParser.mentions(in: text)
        #expect(mentions.map { text[$0.range] } == ["very hot oven", "gas mark 4", "160 degrees C fan or 325°F"])
        #expect(mentions[0].temperature.primary == Temperature(9, .gasMark))
        #expect(mentions[1].temperature.primary == Temperature(4, .gasMark))
        #expect(mentions[2].temperature.alternatives == [Temperature(160, .celsius, fan: true), Temperature(325, .fahrenheit)])
    }

    @Test func leavesOrdinaryTextAlone() {
        for text in [
            "Add 2 C flour and 1 t salt.",
            "Simmer for 20 minutes, stirring.",
            "Cook over a gas flame until charred.",
            "Serve hot with a cool salad.",
            "Whisk 3 eggs with 180 g sugar.",
            "Marinate for 180 minutes.",
            "Reduce by 180 ml.",
            "Preheat the oven to 350 degrees.",
            "Preheat the oven to 350° degrees.",
            "Preheat the oven to 350º degrees and wait.",
        ] {
            #expect(TemperatureParser.mentions(in: text).isEmpty, Comment(rawValue: text))
        }
    }

    @Test func mentionRangesIndexTheOriginalString() {
        let text = "Préchauffez le four à 180 °C (th. 6) — 350°F."
        let mentions = TemperatureParser.mentions(in: text)
        #expect(mentions.count == 2)
        #expect(mentions.map { String(text[$0.range]) } == ["180 °C", "350°F"], "th. 6 is not a form we read, so the two are separate")
        var rebuilt = text
        for mention in mentions.reversed() {
            rebuilt.replaceSubrange(mention.range, with: "[\(mention.temperature.formatted(in: .fahrenheit))]")
        }
        #expect(rebuilt == "Préchauffez le four à [355°F] (th. 6) — [350°F].")
    }

    @Test func renderingPillsInPlace() {
        let text = "Heat the oven to 200°C (180°C fan), gas 6, 400°F. Roast 40 min, then rest; the centre should read 55°C."
        var rendered = text
        for mention in TemperatureParser.mentions(in: text).reversed() {
            rendered.replaceSubrange(mention.range, with: "[\(mention.temperature.formatted(in: .fahrenheit))]")
        }
        #expect(rendered == "Heat the oven to [400°F]. Roast 40 min, then rest; the centre should read [130°F].")
        var celsius = text
        for mention in TemperatureParser.mentions(in: text).reversed() {
            celsius.replaceSubrange(mention.range, with: "[\(mention.temperature.formatted(in: .celsius))]")
        }
        #expect(celsius == "Heat the oven to [200°C]. Roast 40 min, then rest; the centre should read [55°C].")
    }

    @Test func originalTextIsKeptAlongsideTheConversion() {
        let parsed = try! #require(TemperatureParser.parse("Gas Mark 6"))
        #expect(parsed.originalText == "Gas Mark 6")
        #expect(parsed.formatted(in: .fahrenheit) == "400°F")
        #expect(parsed.formatted(in: .celsius) == "200°C")
        #expect(parsed.formatted(in: .gasMark) == "gas 6")
    }

    @Test func parsedTemperatureIsCodable() throws {
        let parsed = try #require(TemperatureParser.parse("200°C (180°C fan), gas 6, 400°F"))
        let data = try JSONEncoder().encode(parsed)
        #expect(try JSONDecoder().decode(ParsedTemperature.self, from: data) == parsed)
    }

    @Test func formattingRoundTripsThroughTheParser() {
        for scale in TemperatureScale.allCases {
            for style in TemperatureNameStyle.allCases {
                for degrees in [Rational(1, 4), Rational(1, 2), 1, 4, 9, 10, 150, 180, 350, 475] as [Rational] {
                    if scale != .gasMark && degrees < 10 { continue }  // formatted "1°F" parses, but keep to oven-ish values
                    for fan in [false, true] {
                        let temperature = Temperature(degrees, scale, fan: fan)
                        let text = temperature.formatted(style: style)
                        #expect(TemperatureParser.parse(text)?.primary == temperature, Comment(rawValue: text))
                    }
                }
            }
        }
    }
}
