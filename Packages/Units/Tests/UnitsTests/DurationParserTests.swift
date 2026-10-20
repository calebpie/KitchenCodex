import Foundation
import Testing
@testable import Units

@Suite("Duration parser")
struct DurationParserTests {
    @Test(arguments: [
        ("12 minutes", CookingDuration(minutes: 12)),
        ("12 minute", CookingDuration(minutes: 12)),
        ("12 min", CookingDuration(minutes: 12)),
        ("12 mins", CookingDuration(minutes: 12)),
        ("12 min.", CookingDuration(minutes: 12)),
        ("12m", CookingDuration(minutes: 12)),
        ("12mins", CookingDuration(minutes: 12)),
        ("12 Minutes", CookingDuration(minutes: 12)),
        ("12 MIN", CookingDuration(minutes: 12)),
        ("  12 minutes  ", CookingDuration(minutes: 12)),
        ("(12 minutes)", CookingDuration(minutes: 12)),
        ("12 minutes.", CookingDuration(minutes: 12)),
        ("12 minutes,", CookingDuration(minutes: 12)),
        ("1 hour", CookingDuration(hours: 1)),
        ("1 hr", CookingDuration(hours: 1)),
        ("1 hr.", CookingDuration(hours: 1)),
        ("1 h", CookingDuration(hours: 1)),
        ("1h", CookingDuration(hours: 1)),
        ("1hr", CookingDuration(hours: 1)),
        ("2 hours", CookingDuration(hours: 2)),
        ("2 hrs", CookingDuration(hours: 2)),
        ("2hrs", CookingDuration(hours: 2)),
        ("24 hours", CookingDuration(hours: 24)),
        ("1 hr 30 min", CookingDuration(minutes: 90)),
        ("1 hour 30 minutes", CookingDuration(minutes: 90)),
        ("1 hour and 30 minutes", CookingDuration(minutes: 90)),
        ("1 hr 30 mins", CookingDuration(minutes: 90)),
        ("1hr30min", CookingDuration(minutes: 90)),
        ("1 h 30 min", CookingDuration(minutes: 90)),
        ("1h30", CookingDuration(minutes: 90)),
        ("1h30m", CookingDuration(minutes: 90)),
        ("1h 30m", CookingDuration(minutes: 90)),
        ("1h30m15s", CookingDuration(seconds: 5415)),
        ("1m30s", CookingDuration(seconds: 90)),
        ("1min30sec", CookingDuration(seconds: 90)),
        ("2 hours 15 minutes 30 seconds", CookingDuration(seconds: 8130)),
        ("1 minute 30 seconds", CookingDuration(seconds: 90)),
        ("1:30 hours", CookingDuration(minutes: 90)),
        ("1:30 hr", CookingDuration(minutes: 90)),
        ("1:30h", CookingDuration(minutes: 90)),
        ("2:30 minutes", CookingDuration(seconds: 150)),
        ("0:45 min", CookingDuration(seconds: 45)),
        ("1½ hours", CookingDuration(minutes: 90)),
        ("1 ½ hours", CookingDuration(minutes: 90)),
        ("1 1/2 hours", CookingDuration(minutes: 90)),
        ("1-1/2 hours", CookingDuration(minutes: 90)),
        ("1.5 hours", CookingDuration(minutes: 90)),
        ("1.25 hours", CookingDuration(minutes: 75)),
        ("1¼ hours", CookingDuration(minutes: 75)),
        ("1⅓ hours", CookingDuration(minutes: 80)),
        ("½ hour", CookingDuration(minutes: 30)),
        ("1/2 hour", CookingDuration(minutes: 30)),
        ("¾ hour", CookingDuration(minutes: 45)),
        ("3/4 hour", CookingDuration(minutes: 45)),
        ("2.5 minutes", CookingDuration(seconds: 150)),
        ("90 seconds", CookingDuration(seconds: 90)),
        ("45 sec", CookingDuration(seconds: 45)),
        ("45 secs", CookingDuration(seconds: 45)),
        ("30 second", CookingDuration(seconds: 30)),
        ("1 second", CookingDuration(seconds: 1)),
        ("2 days", CookingDuration(2, .days)),
        ("1 day", CookingDuration(1, .days)),
        ("a day", CookingDuration(1, .days)),
        ("overnight", CookingDuration.overnight),
        ("Overnight", CookingDuration(hours: 12)),
        ("overnight.", CookingDuration(hours: 12)),
    ] as [(String, CookingDuration)])
    func parsesSingleForms(text: String, duration: CookingDuration) {
        let parsed = DurationParser.parse(text)
        #expect(parsed?.lower == duration)
        #expect(parsed?.duration == duration)
        #expect(parsed?.upper == nil)
        #expect(parsed?.isRange == false)
        #expect(DurationParser().parse(text)?.lower == duration)
        #expect(CookingDuration(parsing: text) == duration)
    }

    @Test(arguments: [
        ("about 20 minutes", CookingDuration(minutes: 20)),
        ("About 20 minutes", CookingDuration(minutes: 20)),
        ("approximately 20 minutes", CookingDuration(minutes: 20)),
        ("approx. 20 minutes", CookingDuration(minutes: 20)),
        ("around 20 minutes", CookingDuration(minutes: 20)),
        ("roughly 20 minutes", CookingDuration(minutes: 20)),
        ("at least 20 minutes", CookingDuration(minutes: 20)),
        ("at most 10 minutes", CookingDuration(minutes: 10)),
        ("no more than 10 minutes", CookingDuration(minutes: 10)),
        ("up to 2 days", CookingDuration(2, .days)),
        ("nearly an hour", CookingDuration(hours: 1)),
        ("almost an hour", CookingDuration(hours: 1)),
        ("just under 2 hours", CookingDuration(hours: 2)),
        ("under 10 minutes", CookingDuration(minutes: 10)),
        ("another 5 minutes", CookingDuration(minutes: 5)),
        ("another minute", CookingDuration(minutes: 1)),
        ("another hour", CookingDuration(hours: 1)),
        ("an additional 5 minutes", CookingDuration(minutes: 5)),
        ("an additional minute", CookingDuration(minutes: 1)),
        ("a further 10 minutes", CookingDuration(minutes: 10)),
        ("an extra minute", CookingDuration(minutes: 1)),
        ("5 more minutes", CookingDuration(minutes: 5)),
        ("five more minutes", CookingDuration(minutes: 5)),
        ("5 additional minutes", CookingDuration(minutes: 5)),
        ("10 minutes more", CookingDuration(minutes: 10)),
        ("10 minutes longer", CookingDuration(minutes: 10)),
        ("20 minutes or so", CookingDuration(minutes: 20)),
        ("a good 20 minutes", CookingDuration(minutes: 20)),
        ("a full hour", CookingDuration(hours: 1)),
        ("a full 10 minutes", CookingDuration(minutes: 10)),
        ("at least another 10 minutes", CookingDuration(minutes: 10)),
        ("for 20 minutes", CookingDuration(minutes: 20)),
        ("For 20 minutes", CookingDuration(minutes: 20)),
        ("for about 20 minutes", CookingDuration(minutes: 20)),
        ("20-minute", CookingDuration(minutes: 20)),
        ("20 minute", CookingDuration(minutes: 20)),
        ("20-min", CookingDuration(minutes: 20)),
        ("two-hour", CookingDuration(hours: 2)),
        ("90-second", CookingDuration(seconds: 90)),
        ("one-hour", CookingDuration(hours: 1)),
        ("24-hour", CookingDuration(hours: 24)),
        ("five minutes", CookingDuration(minutes: 5)),
        ("Five Minutes", CookingDuration(minutes: 5)),
        ("ten minutes", CookingDuration(minutes: 10)),
        ("fifteen minutes", CookingDuration(minutes: 15)),
        ("twenty minutes", CookingDuration(minutes: 20)),
        ("twenty-five minutes", CookingDuration(minutes: 25)),
        ("twenty five minutes", CookingDuration(minutes: 25)),
        ("ninety seconds", CookingDuration(seconds: 90)),
        ("one minute", CookingDuration(minutes: 1)),
        ("one second", CookingDuration(seconds: 1)),
        ("one hour", CookingDuration(hours: 1)),
        ("two hours", CookingDuration(hours: 2)),
        ("two and a half hours", CookingDuration(minutes: 150)),
        ("one and a half hours", CookingDuration(minutes: 90)),
        ("1 and a half hours", CookingDuration(minutes: 90)),
        ("an hour", CookingDuration(hours: 1)),
        ("An hour", CookingDuration(hours: 1)),
        ("a minute", CookingDuration(minutes: 1)),
        ("half an hour", CookingDuration(minutes: 30)),
        ("Half an Hour", CookingDuration(minutes: 30)),
        ("a half hour", CookingDuration(minutes: 30)),
        ("a half-hour", CookingDuration(minutes: 30)),
        ("half-hour", CookingDuration(minutes: 30)),
        ("half hour", CookingDuration(minutes: 30)),
        ("half a minute", CookingDuration(seconds: 30)),
        ("an hour and a half", CookingDuration(minutes: 90)),
        ("an hour and a quarter", CookingDuration(minutes: 75)),
        ("2 hours and a half", CookingDuration(minutes: 150)),
    ] as [(String, CookingDuration)])
    func parsesQualifiedAndSpelledOutForms(text: String, duration: CookingDuration) {
        let parsed = DurationParser.parse(text)
        #expect(parsed?.lower == duration)
        #expect(parsed?.upper == nil)
        #expect(CookingDuration(parsing: text) == duration)
    }

    @Test(arguments: [
        ("8–10 minutes", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("8-10 minutes", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("8 – 10 minutes", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("8—10 minutes", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("8 to 10 minutes", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("8 to 10 min", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("8 TO 10 MINUTES", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("5 or 6 minutes", CookingDuration(minutes: 5), CookingDuration(minutes: 6)),
        ("between 8 and 10 minutes", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("from 8 to 10 minutes", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("20–30 min.", CookingDuration(minutes: 20), CookingDuration(minutes: 30)),
        ("1 to 2 hours", CookingDuration(hours: 1), CookingDuration(hours: 2)),
        ("1–2 hours", CookingDuration(hours: 1), CookingDuration(hours: 2)),
        ("1 to 1½ hours", CookingDuration(hours: 1), CookingDuration(minutes: 90)),
        ("1–1½ hours", CookingDuration(hours: 1), CookingDuration(minutes: 90)),
        ("1½ to 2 hours", CookingDuration(minutes: 90), CookingDuration(hours: 2)),
        ("1 1/2 to 2 hours", CookingDuration(minutes: 90), CookingDuration(hours: 2)),
        ("45 minutes to 1 hour", CookingDuration(minutes: 45), CookingDuration(hours: 1)),
        ("45 min – 1 hr", CookingDuration(minutes: 45), CookingDuration(hours: 1)),
        ("between 45 minutes and 1 hour", CookingDuration(minutes: 45), CookingDuration(hours: 1)),
        ("between 1 and 2 hours", CookingDuration(hours: 1), CookingDuration(hours: 2)),
        ("one to two hours", CookingDuration(hours: 1), CookingDuration(hours: 2)),
        ("two or three minutes", CookingDuration(minutes: 2), CookingDuration(minutes: 3)),
        ("an hour or two", CookingDuration(hours: 1), CookingDuration(hours: 2)),
        ("a minute or two", CookingDuration(minutes: 1), CookingDuration(minutes: 2)),
        ("about 8–10 minutes", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("8–10 more minutes", CookingDuration(minutes: 8), CookingDuration(minutes: 10)),
        ("10 minutes or up to 1 hour", CookingDuration(minutes: 10), CookingDuration(hours: 1)),
        ("8 hours or overnight", CookingDuration(hours: 8), CookingDuration(hours: 12)),
        ("2 hours, or overnight", CookingDuration(hours: 2), CookingDuration(hours: 12)),
        ("30 minutes to an hour", CookingDuration(minutes: 30), CookingDuration(hours: 1)),
        ("another 2 to 3 minutes", CookingDuration(minutes: 2), CookingDuration(minutes: 3)),
        ("overnight or up to 2 days", CookingDuration(hours: 12), CookingDuration(2, .days)),
        ("1 hour to 1 hour 30 minutes", CookingDuration(hours: 1), CookingDuration(minutes: 90)),
        ("2 to 3 days", CookingDuration(2, .days), CookingDuration(3, .days)),
        ("30 to 45 seconds", CookingDuration(seconds: 30), CookingDuration(seconds: 45)),
        ("1h30 to 2h00", CookingDuration(minutes: 90), CookingDuration(hours: 2)),
    ] as [(String, CookingDuration, CookingDuration)])
    func keepsBothEndsOfARange(text: String, lower: CookingDuration, upper: CookingDuration) {
        let parsed = DurationParser.parse(text)
        #expect(parsed?.lower == lower)
        #expect(parsed?.upper == upper)
        #expect(parsed?.isRange == true)
        #expect(parsed?.duration == lower, "a single value reads the low end")
        #expect(CookingDuration(parsing: text) == lower)
    }

    @Test(arguments: [
        "", " ", "12", "12 m", "12 s", "30s", "2 C", "2 c", "2 c flour", "5 ml", "5 mm", "2 hot peppers",
        "a few minutes", "a couple of minutes", "a couple minutes", "several minutes", "some minutes",
        "minutes", "hour", "an", "half", "half the time", "and a half",
        "last-minute", "last minute", "at the last minute", "second bowl", "a second", "a second bowl",
        "the second hour", "1:30", "1:30 pm", "10:30 am", "12 months", "6 minced cloves", "3 sections",
        "3 secrets", "5 minimum", "1 hourly", "2 day-old bread", "two-day-old bread", "overnight oats",
        "an overnight rest", "0 minutes", "8 and 10 minutes", "350 degrees", "350°F for 20 minutes",
        "Bake 20 minutes", "20 minutes then 30 minutes", "1 hour, 30 minutes", "12 minutes 1 hour",
        "two minutes 10", "min 5", "hours 2", "2 h2o",
    ])
    func rejectsWhatIsNotAWholeDuration(text: String) {
        #expect(DurationParser.parse(text) == nil)
        #expect(CookingDuration(parsing: text) == nil)
    }

    @Test func keepsTheOriginalText() {
        for text in ["12 minutes", "about 20 minutes", "8–10 minutes", "1 hour and 30 minutes", "overnight", "an hour or two"] {
            #expect(DurationParser.parse(text)?.originalText == text, Comment(rawValue: text))
        }
        #expect(DurationParser.parse("(12 minutes)")?.originalText == "12 minutes")
        #expect(DurationParser.parse("for 20 minutes")?.originalText == "20 minutes", "the preposition is not part of the duration")
    }

    @Test func overnightIsTwelveHoursAndSaysSo() {
        let parsed = try! #require(DurationParser.parse("overnight"))
        #expect(parsed.lower == CookingDuration(hours: 12))
        #expect(parsed.isOvernight)
        #expect(parsed.formatted() == "overnight")
        #expect(parsed.formatted(style: .full) == "overnight")
        #expect(DurationParser.parse("12 hours")?.isOvernight == false)
        #expect(DurationParser.parse("8 hours or overnight")?.isOvernight == false, "a range is not the word alone")
    }

    // MARK: - In a sentence

    @Test func findsOneMentionWithItsRange() {
        let text = "Simmer for 20 minutes, stirring now and then."
        let mentions = DurationParser.mentions(in: text)
        #expect(mentions.count == 1)
        let mention = try! #require(mentions.first)
        #expect(text[mention.range] == "20 minutes")
        #expect(mention.originalText == "20 minutes")
        #expect(mention.duration.lower == CookingDuration(minutes: 20))
        #expect(mention.duration.upper == nil)
        #expect(DurationParser().mentions(in: text) == mentions)
    }

    @Test func includesQualifiersInTheRun() {
        let golden = "Cook until golden, about 20 minutes."
        #expect(DurationParser.mentions(in: golden).map { golden[$0.range] } == ["about 20 minutes"])

        let more = "Cook for another 5 minutes, then 5 more minutes, then 2 minutes longer."
        #expect(DurationParser.mentions(in: more).map { more[$0.range] } == ["another 5 minutes", "5 more minutes", "2 minutes longer"])

        let least = "Chill for at least an hour or up to 2 days."
        let mentions = DurationParser.mentions(in: least)
        #expect(mentions.map { least[$0.range] } == ["at least an hour or up to 2 days"])
        #expect(mentions.first?.duration.lower == CookingDuration(hours: 1))
        #expect(mentions.first?.duration.upper == CookingDuration(2, .days))
    }

    @Test func findsAdjectiveForms() {
        let text = "Give the dough a 20-minute rest and then a 2 hour rise."
        let mentions = DurationParser.mentions(in: text)
        #expect(mentions.map { text[$0.range] } == ["20-minute", "2 hour"])
        #expect(mentions.map(\.duration.lower) == [CookingDuration(minutes: 20), CookingDuration(hours: 2)])
    }

    @Test func compoundsAndRangesInOneSentence() {
        let text = "Bake 1 hour 15 minutes, then rest 10 to 15 minutes before slicing."
        let mentions = DurationParser.mentions(in: text)
        #expect(mentions.map { text[$0.range] } == ["1 hour 15 minutes", "10 to 15 minutes"])
        #expect(mentions[0].duration.lower == CookingDuration(minutes: 75))
        #expect(mentions[0].duration.upper == nil)
        #expect(mentions[1].duration.lower == CookingDuration(minutes: 10))
        #expect(mentions[1].duration.upper == CookingDuration(minutes: 15))
    }

    @Test func separatesMentionsThatAreNotARange() {
        let then = "Cook 10 minutes, then 20 minutes more."
        #expect(DurationParser.mentions(in: then).map { then[$0.range] } == ["10 minutes", "20 minutes more"])

        let down = "Reduce the time from 1 hour to 30 minutes."
        #expect(DurationParser.mentions(in: down).map { down[$0.range] } == ["1 hour", "30 minutes"], "a falling pair is not a range")

        let comma = "Freeze 2 hours or until firm, then 1 hour, or overnight if you like; cook 1–2 hours or overnight."
        #expect(DurationParser.mentions(in: comma).map { comma[$0.range] } == ["2 hours", "1 hour, or overnight", "1–2 hours", "overnight"],
                "a range already written with two ends does not take a third")

        let same = "Stir for 1 minute and 1 minute again."
        #expect(DurationParser.mentions(in: same).map { same[$0.range] } == ["1 minute", "1 minute"])

        let list = "Prep 10 minutes; cook 20 minutes; total 30 minutes."
        #expect(DurationParser.mentions(in: list).map(\.duration.lower) == [
            CookingDuration(minutes: 10), CookingDuration(minutes: 20), CookingDuration(minutes: 30),
        ])
    }

    @Test func temperaturesAndQuantitiesAreNotDurations() {
        let text = "Bake at 180°C (350°F) for 25 minutes with 2 C flour and 5 ml vanilla."
        #expect(DurationParser.mentions(in: text).map { text[$0.range] } == ["25 minutes"])
        #expect(TemperatureParser.mentions(in: text).map { text[$0.range] } == ["180°C (350°F)"])
    }

    @Test func clockTimesAreLeftAlone() {
        let clock = "Serve at 1:30, or 7:45 at the latest."
        #expect(DurationParser.mentions(in: clock).isEmpty)
        let hours = "Braise 1:30 hours, then rest 0:15 min."
        let mentions = DurationParser.mentions(in: hours)
        #expect(mentions.map { hours[$0.range] } == ["1:30 hours", "0:15 min"])
        #expect(mentions.map(\.duration.lower) == [CookingDuration(minutes: 90), CookingDuration(seconds: 15)])
    }

    @Test func overnightNeedsToStandAlone() {
        let fridge = "Refrigerate overnight, covered."
        #expect(DurationParser.mentions(in: fridge).map { fridge[$0.range] } == ["overnight"])
        let upTo = "Marinate overnight or up to 2 days in the fridge."
        #expect(DurationParser.mentions(in: upTo).map { upTo[$0.range] } == ["overnight or up to 2 days"])
        let end = "Let the dough rise overnight"
        #expect(DurationParser.mentions(in: end).map { end[$0.range] } == ["overnight"])
        let oats = "Make the overnight oats the evening before."
        #expect(DurationParser.mentions(in: oats).isEmpty)
        let rise = "An overnight rise gives more flavour."
        #expect(DurationParser.mentions(in: rise).isEmpty)
    }

    @Test func leavesOrdinaryTextAlone() {
        for text in [
            "Add 2 C flour and 1 t salt.",
            "Preheat the oven to 350°F.",
            "Stir in a second bowl, then add the second egg.",
            "A last-minute garnish of parsley.",
            "Serve at 1:30 pm.",
            "Measure 12 m of twine and 5 ml of vanilla.",
            "Cut 2 day-old bread into cubes.",
            "Serves 2 to 4.",
            "Add a few minutes if the pan is crowded.",
            "Keeps for 6 months in the freezer.",
            "Use 6 minced cloves and 3 sections of orange.",
            "The minimum is 5 minimum-size eggs.",
            "Whisk 3 eggs with 180 g sugar.",
            "Reduce by 180 ml.",
            "Set a timer.",
        ] {
            #expect(DurationParser.mentions(in: text).isEmpty, Comment(rawValue: text))
        }
    }

    @Test func rangesAreInOrderAndDoNotOverlap() {
        let text = "Rest 5 minutes. Bake 20–25 minutes at 200°C, turn, bake 10 more minutes, cool 1 hour and 30 minutes, chill overnight."
        let mentions = DurationParser.mentions(in: text)
        #expect(mentions.map { text[$0.range] } == ["5 minutes", "20–25 minutes", "10 more minutes", "1 hour and 30 minutes", "overnight"])
        for (earlier, later) in zip(mentions, mentions.dropFirst()) {
            #expect(earlier.range.upperBound <= later.range.lowerBound)
        }
    }

    @Test func mentionRangesIndexTheOriginalString() {
        let text = "Laissez reposer 10 minutes — puis cuire 1 h 30 min à feu doux, « about 2 hours » in all."
        let mentions = DurationParser.mentions(in: text)
        #expect(mentions.map { String(text[$0.range]) } == ["10 minutes", "1 h 30 min", "about 2 hours"])
        var rebuilt = text
        for mention in mentions.reversed() {
            rebuilt.replaceSubrange(mention.range, with: "[\(mention.duration.formatted())]")
        }
        #expect(rebuilt == "Laissez reposer [10 min] — puis cuire [1 hr 30 min] à feu doux, « [2 hr] » in all.")
    }

    @Test func renderingPillsInPlace() {
        let text = "Roast 40 min, then rest for 8–10 minutes; chill overnight or up to 2 days. Whisk for 90 seconds."
        var rendered = text
        for mention in DurationParser.mentions(in: text).reversed() {
            rendered.replaceSubrange(mention.range, with: "[\(mention.duration.formatted())]")
        }
        #expect(rendered == "Roast [40 min], then rest for [8–10 min]; chill [overnight–2 days]. Whisk for [90 sec].")
        var spoken = text
        for mention in DurationParser.mentions(in: text).reversed() {
            spoken.replaceSubrange(mention.range, with: "[\(mention.duration.formatted(style: .full))]")
        }
        #expect(spoken == "Roast [40 minutes], then rest for [8 to 10 minutes]; chill [overnight to 2 days]. Whisk for [90 seconds].")
    }

    @Test func parsedDurationIsCodable() throws {
        for text in ["12 minutes", "1 hour 30 minutes", "8–10 minutes", "45 minutes to 1 hour", "overnight", "1½ hours"] {
            let parsed = try #require(DurationParser.parse(text))
            let data = try JSONEncoder().encode(parsed)
            let decoded = try JSONDecoder().decode(ParsedDuration.self, from: data)
            #expect(decoded == parsed, Comment(rawValue: text))
            #expect(decoded.formatted() == parsed.formatted(), Comment(rawValue: text))
        }
    }

    // MARK: - The value inside a mention

    @Test(arguments: [
        ("Salt up to 2 days ahead.", "up to 2 days", "2 days"),
        ("Marinate at least 6 hours.", "at least 6 hours", "6 hours"),
        ("Cook another 10–30 minutes.", "another 10–30 minutes", "10–30 minutes"),
        ("Cook another 10 to 30 minutes.", "another 10 to 30 minutes", "10 to 30 minutes"),
        ("Roast 30 to 40 minutes longer.", "30 to 40 minutes longer", "30 to 40 minutes"),
        ("Simmer about 5 minutes more.", "about 5 minutes more", "5 minutes"),
        ("Rest 5 minutes or so.", "5 minutes or so", "5 minutes"),
        ("Rest about 8–10 minutes.", "about 8–10 minutes", "8–10 minutes"),
        ("Rest for a good 20 minutes.", "a good 20 minutes", "20 minutes"),
        ("Cook for at least another 10 minutes.", "at least another 10 minutes", "10 minutes"),
        ("Simmer about 2 hours and a half.", "about 2 hours and a half", "2 hours and a half"),
        ("Bake 1 hr 15 min.", "1 hr 15 min", "1 hr 15 min"),
        ("Braise 1 hour and 15 minutes.", "1 hour and 15 minutes", "1 hour and 15 minutes"),
        ("Bake about 1 hour 15 minutes.", "about 1 hour 15 minutes", "1 hour 15 minutes"),
        ("Bake 1 hour 15 minutes longer.", "1 hour 15 minutes longer", "1 hour 15 minutes"),
        ("Simmer between 8 and 10 minutes.", "between 8 and 10 minutes", "between 8 and 10 minutes"),
        ("Rest 45 minutes to 1 hour longer.", "45 minutes to 1 hour longer", "45 minutes to 1 hour"),
        ("Rest from about 45 minutes to 1 hour.", "from about 45 minutes to 1 hour", "45 minutes to 1 hour"),
        ("Chill at least an hour or up to 2 days.", "at least an hour or up to 2 days", "an hour or up to 2 days"),
        ("Stir for a minute or two.", "a minute or two", "a minute or two"),
        ("Cook 5 more minutes.", "5 more minutes", "5 more minutes"),
        ("Chill overnight.", "overnight", "overnight"),
        ("Proof 8 hours or overnight.", "8 hours or overnight", "8 hours or overnight"),
        ("Braise 1:30 hours.", "1:30 hours", "1:30 hours"),
        ("Bake 1h30.", "1h30", "1h30"),
        ("Simmer 20 minutes.", "20 minutes", "20 minutes"),
    ] as [(String, String, String)])
    func valueRangeCoversTheNumberAndUnit(text: String, mentionText: String, valueText: String) throws {
        let mentions = DurationParser.mentions(in: text)
        #expect(mentions.count == 1)
        let mention = try #require(mentions.first)
        #expect(String(text[mention.range]) == mentionText, "the mention keeps its qualifiers")
        #expect(mention.originalText == mentionText)
        #expect(String(text[mention.valueRange]) == valueText)
        #expect(mention.range.lowerBound <= mention.valueRange.lowerBound)
        #expect(mention.valueRange.upperBound <= mention.range.upperBound)
    }

    @Test func aMentionWithNoQualifierIsAllValue() {
        let text = "Rest 12 minutes, bake 1 hr 30 min, then 1h30, 8–10 minutes, 45 minutes to 1 hour, "
            + "an hour or two, a 20-minute rest, 1:30 hours, 2 hours and a half, and chill overnight."
        let mentions = DurationParser.mentions(in: text)
        #expect(mentions.map { String(text[$0.range]) } == [
            "12 minutes", "1 hr 30 min", "1h30", "8–10 minutes", "45 minutes to 1 hour",
            "an hour or two", "20-minute", "1:30 hours", "2 hours and a half", "overnight",
        ])
        for mention in mentions {
            #expect(mention.valueRange == mention.range, Comment(rawValue: String(text[mention.range])))
        }
    }

    @Test func aMentionMadeInCodeIsAllValueUnlessToldOtherwise() throws {
        let text = "about 20 minutes"
        let duration = try #require(DurationParser.parse(text))
        let whole = text.startIndex..<text.endIndex
        #expect(DurationMention(range: whole, duration: duration).valueRange == whole)
        let value = try #require(text.range(of: "20 minutes"))
        #expect(DurationMention(range: whole, valueRange: value, duration: duration).valueRange == value)
    }

    @Test func pillsCoverTheValueAndLeaveTheQualifiersAsText() {
        let text = "Salt up to 2 days ahead. Marinate at least 6 hours, cook another 10–30 minutes, "
            + "then 30 to 40 minutes longer, and rest about 5 minutes more."
        var rendered = text
        for mention in DurationParser.mentions(in: text).reversed() {
            rendered.replaceSubrange(mention.valueRange, with: "[\(mention.duration.formatted())]")
        }
        #expect(rendered == "Salt up to [2 days] ahead. Marinate at least [6 hr], cook another [10–30 min], "
            + "then [30–40 min] longer, and rest about [5 min] more.")
    }

    // MARK: - Compounds written with periods

    @Test(arguments: [
        ("Cook 1 hr. 15 min. at 300°F.", "1 hr. 15 min", CookingDuration(minutes: 75), "1 hr 15 min", "1 hour 15 minutes"),
        ("Braise 2 hrs. 30 mins. covered.", "2 hrs. 30 mins", CookingDuration(minutes: 150), "2 hr 30 min", "2 hours 30 minutes"),
        ("Cook 1 hr. and 15 min. at 300°F.", "1 hr. and 15 min", CookingDuration(minutes: 75), "1 hr 15 min", "1 hour 15 minutes"),
        ("Whisk 1 min. 30 sec. until pale.", "1 min. 30 sec", CookingDuration(seconds: 90), "1 min 30 sec", "1 minute 30 seconds"),
        ("Smoke 2 hrs. 15 min. 30 sec. exactly.", "2 hrs. 15 min. 30 sec", CookingDuration(seconds: 8130),
         "2 hr 15 min 30 sec", "2 hours 15 minutes 30 seconds"),
        ("Bake about 1 hr. 15 min. in all.", "about 1 hr. 15 min", CookingDuration(minutes: 75), "1 hr 15 min", "1 hour 15 minutes"),
    ] as [(String, String, CookingDuration, String, String)])
    func aPeriodAfterAnAbbreviatedUnitStillCompounds(text: String, mentionText: String, duration: CookingDuration,
                                                     abbreviated: String, full: String) throws {
        let mentions = DurationParser.mentions(in: text)
        #expect(mentions.count == 1)
        let mention = try #require(mentions.first)
        #expect(String(text[mention.range]) == mentionText, "the final period stays outside")
        #expect(mention.duration.lower == duration)
        #expect(mention.duration.upper == nil)
        #expect(mention.duration.formatted(style: .abbreviated) == abbreviated)
        #expect(mention.duration.formatted(style: .full) == full)
        #expect(String(text[mention.valueRange]) == mentionText.replacingOccurrences(of: "about ", with: ""))
    }

    @Test func periodCompoundsParseAlone() {
        #expect(DurationParser.parse("1 hr. 15 min.")?.lower == CookingDuration(minutes: 75))
        #expect(DurationParser.parse("1 hr. 15 min.")?.originalText == "1 hr. 15 min")
        #expect(DurationParser.parse("2 hrs. 30 mins.")?.formatted() == "2 hr 30 min")
    }

    @Test(arguments: [
        ("Cook 1 hr. Then stir for 15 min.", ["1 hr", "15 min"]),
        ("Smoke 1 hr. 15 lb of brisket feeds a crowd.", ["1 hr"]),
        ("Cook 1 hr. About 15 min before the end, add the peas.", ["1 hr", "About 15 min"]),
        ("Rest 1 hr. A minute before serving, slice.", ["1 hr", "A minute"]),
        ("Rest 1 hr. Fifteen minutes before serving, slice.", ["1 hr", "Fifteen minutes"]),
        ("Rest 1 hour. 15 minutes before serving, slice.", ["1 hour", "15 minutes"]),
        ("Bake 15 min. 1 hr later, glaze.", ["15 min", "1 hr"]),
        ("Simmer 10 min. 5 min more if needed.", ["10 min", "5 min more"]),
        ("Bake 1 hr. 15–20 min. more if needed.", ["1 hr", "15–20 min"]),
    ] as [(String, [String])])
    func aPeriodThatEndsASentenceDoesNotCompound(text: String, mentions expected: [String]) {
        #expect(DurationParser.mentions(in: text).map { String(text[$0.range]) } == expected)
    }

    // MARK: - Formatting

    @Test(arguments: [
        ("12 minutes", "12 min", "12 minutes"),
        ("12m", "12 min", "12 minutes"),
        ("1 minute", "1 min", "1 minute"),
        ("1 second", "1 sec", "1 second"),
        ("1 hour", "1 hr", "1 hour"),
        ("90 minutes", "90 min", "90 minutes"),
        ("90 seconds", "90 sec", "90 seconds"),
        ("24 hours", "24 hr", "24 hours"),
        ("1 hour 30 minutes", "1 hr 30 min", "1 hour 30 minutes"),
        ("1 hour and 30 minutes", "1 hr 30 min", "1 hour 30 minutes"),
        ("1h30", "1 hr 30 min", "1 hour 30 minutes"),
        ("1h30m15s", "1 hr 30 min 15 sec", "1 hour 30 minutes 15 seconds"),
        ("1m30s", "1 min 30 sec", "1 minute 30 seconds"),
        ("1:30 hours", "1 hr 30 min", "1 hour 30 minutes"),
        ("2:30 minutes", "2 min 30 sec", "2 minutes 30 seconds"),
        ("1½ hours", "1½ hr", "1 hour 30 minutes"),
        ("1 1/2 hours", "1½ hr", "1 hour 30 minutes"),
        ("1.5 hours", "1½ hr", "1 hour 30 minutes"),
        ("1.25 hours", "1¼ hr", "1 hour 15 minutes"),
        ("1.3 hours", "1 hr 18 min", "1 hour 18 minutes"),
        ("half an hour", "½ hr", "30 minutes"),
        ("an hour and a half", "1½ hr", "1 hour 30 minutes"),
        ("two and a half hours", "2½ hr", "2 hours 30 minutes"),
        ("2.5 minutes", "2½ min", "2 minutes 30 seconds"),
        ("½ second", "½ sec", "0.5 seconds"),
        ("2 days", "2 days", "2 days"),
        ("1 day", "1 day", "1 day"),
        ("1½ days", "1½ days", "1 day 12 hours"),
        ("overnight", "overnight", "overnight"),
        ("about 20 minutes", "20 min", "20 minutes"),
        ("another 5 minutes", "5 min", "5 minutes"),
        ("20-minute", "20 min", "20 minutes"),
        ("five minutes", "5 min", "5 minutes"),
        ("8–10 minutes", "8–10 min", "8 to 10 minutes"),
        ("8 to 10 min", "8–10 min", "8 to 10 minutes"),
        ("between 8 and 10 minutes", "8–10 min", "8 to 10 minutes"),
        ("1 to 1½ hours", "1–1½ hr", "1 hour to 1 hour 30 minutes"),
        ("1½ to 2 hours", "1½–2 hr", "1 hour 30 minutes to 2 hours"),
        ("45 minutes to 1 hour", "45 min–1 hr", "45 minutes to 1 hour"),
        ("1 hour to 1 hour 30 minutes", "1 hr–1 hr 30 min", "1 hour to 1 hour 30 minutes"),
        ("an hour or two", "1–2 hr", "1 to 2 hours"),
        ("a minute or two", "1–2 min", "1 to 2 minutes"),
        ("8 hours or overnight", "8 hr–overnight", "8 hours to overnight"),
        ("1 to 2 days", "1–2 days", "1 to 2 days"),
    ] as [(String, String, String)])
    func formatsAsTheRecipeWroteIt(text: String, abbreviated: String, full: String) {
        let parsed = DurationParser.parse(text)
        #expect(parsed?.formatted() == abbreviated)
        #expect(parsed?.formatted(style: .abbreviated) == abbreviated)
        #expect(parsed?.formatted(style: .full) == full)
    }

    @Test func formattingRoundTripsThroughTheParser() {
        for text in [
            "12 minutes", "90 minutes", "1 hour 30 minutes", "1h30m15s", "1½ hours", "1.3 hours", "half an hour",
            "90 seconds", "2 days", "1½ days", "overnight", "8–10 minutes", "45 minutes to 1 hour",
            "1 to 1½ hours", "an hour or two", "8 hours or overnight", "½ second", "1 hour to 1 hour 30 minutes",
        ] {
            let parsed = try! #require(DurationParser.parse(text), Comment(rawValue: text))
            for style in DurationNameStyle.allCases {
                let formatted = parsed.formatted(style: style)
                let again = DurationParser.parse(formatted)
                #expect(again?.lower == parsed.lower, Comment(rawValue: "\(text) → \(formatted)"))
                #expect(again?.upper == parsed.upper, Comment(rawValue: "\(text) → \(formatted)"))
            }
        }
        for duration in [CookingDuration(minutes: 12), CookingDuration(minutes: 90), CookingDuration(seconds: 5415), CookingDuration(hours: 48)] {
            for style in DurationNameStyle.allCases {
                let formatted = duration.formatted(style: style)
                #expect(DurationParser.parse(formatted)?.lower == duration, Comment(rawValue: formatted))
            }
        }
    }
}
