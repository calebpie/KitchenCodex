import Foundation
import Testing
@testable import Units

@Suite("Cooking durations")
struct CookingDurationTests {
    @Test func constructorsAgree() {
        #expect(CookingDuration(minutes: 90) == CookingDuration(seconds: 5400))
        #expect(CookingDuration(hours: Rational(3, 2)) == CookingDuration(seconds: 5400))
        #expect(CookingDuration(90, .minutes) == CookingDuration(seconds: 5400))
        #expect(CookingDuration(2, .days) == CookingDuration(hours: 48))
        #expect(CookingDuration(hours: Rational(1, 3)).seconds == 1200, "a third of an hour is exact")
    }

    @Test func accessorsReadBackExactly() {
        let duration = CookingDuration(minutes: 90)
        #expect(duration.seconds == 5400)
        #expect(duration.minutes == 90)
        #expect(duration.hours == Rational(3, 2))
        #expect(CookingDuration(seconds: 90).minutes == Rational(3, 2))
        #expect(CookingDuration(hours: Rational(1, 3)).minutes == 20)
    }

    @Test(arguments: [
        (CookingDuration(seconds: 5400), 1, 30, Rational(0)),
        (CookingDuration(seconds: 90), 0, 1, Rational(30)),
        (CookingDuration(seconds: Rational(7323, 2)), 1, 1, Rational(3, 2)),  // 3661.5 s
        (CookingDuration(hours: 25), 25, 0, Rational(0)),
        (CookingDuration(seconds: 0), 0, 0, Rational(0)),
    ] as [(CookingDuration, Int, Int, Rational)])
    func componentsAsATimerShowsThem(duration: CookingDuration, hours: Int, minutes: Int, seconds: Rational) {
        let components = duration.components
        #expect(components.hours == hours)
        #expect(components.minutes == minutes)
        #expect(components.seconds == seconds)
    }

    @Test func comparesAndAdds() {
        #expect(CookingDuration(minutes: 8) < CookingDuration(minutes: 10))
        #expect(CookingDuration(hours: 1) > CookingDuration(minutes: 59))
        #expect(CookingDuration(hours: 1) + CookingDuration(minutes: 30) == CookingDuration(minutes: 90))
        #expect(CookingDuration.overnight == CookingDuration(hours: 12))
        #expect(DurationUnit.seconds < .minutes && DurationUnit.minutes < .hours && DurationUnit.hours < .days)
        #expect(DurationUnit.days.seconds == 86_400)
    }

    @Test(arguments: [
        (CookingDuration(minutes: 12), "12 min", "12 minutes"),
        (CookingDuration(seconds: 5400), "1 hr 30 min", "1 hour 30 minutes"),
        (CookingDuration(minutes: 90), "1 hr 30 min", "1 hour 30 minutes"),
        (CookingDuration(hours: Rational(3, 2)), "1 hr 30 min", "1 hour 30 minutes"),
        (CookingDuration(seconds: 90), "1 min 30 sec", "1 minute 30 seconds"),
        (CookingDuration(seconds: 45), "45 sec", "45 seconds"),
        (CookingDuration(seconds: 1), "1 sec", "1 second"),
        (CookingDuration(minutes: 1), "1 min", "1 minute"),
        (CookingDuration(hours: 1), "1 hr", "1 hour"),
        (CookingDuration(hours: 2), "2 hr", "2 hours"),
        (CookingDuration(hours: 48), "48 hr", "48 hours"),
        (CookingDuration(2, .days), "48 hr", "48 hours"),
        (CookingDuration(seconds: 5415), "1 hr 30 min 15 sec", "1 hour 30 minutes 15 seconds"),
        (CookingDuration(seconds: Rational(1, 2)), "½ sec", "0.5 seconds"),
        (CookingDuration(seconds: Rational(0)), "0 sec", "0 seconds"),
        (CookingDuration.overnight, "12 hr", "12 hours"),
    ] as [(CookingDuration, String, String)])
    func formatsInWholeHoursMinutesAndSeconds(duration: CookingDuration, abbreviated: String, full: String) {
        #expect(duration.formatted() == abbreviated)
        #expect(duration.formatted(style: .abbreviated) == abbreviated)
        #expect(duration.formatted(style: .full) == full)
        #expect(duration.description == abbreviated)
    }

    @Test func unitNames() {
        #expect(DurationUnit.minutes.name(style: .abbreviated, plural: true) == "min")
        #expect(DurationUnit.days.name(style: .abbreviated, plural: true) == "days")
        #expect(DurationUnit.days.name(style: .abbreviated, plural: false) == "day")
        #expect(DurationUnit.hours.name(style: .full, plural: false) == "hour")
        #expect(DurationUnit.seconds.name(style: .full, plural: true) == "seconds")
    }

    @Test func aDurationMadeInCodeFormatsCanonically() {
        let single = ParsedDuration(lower: CookingDuration(minutes: 90), originalText: "ninety minutes")
        #expect(single.formatted() == "1 hr 30 min")
        #expect(single.isRange == false)
        #expect(single.isOvernight == false)
        let range = ParsedDuration(lower: CookingDuration(minutes: 90), upper: CookingDuration(hours: 2), originalText: "")
        #expect(range.formatted() == "1 hr 30 min–2 hr")
        #expect(range.formatted(style: .full) == "1 hour 30 minutes to 2 hours")
        #expect(range.isRange)
    }

    @Test func isCodable() throws {
        let duration = CookingDuration(hours: Rational(4, 3))
        let data = try JSONEncoder().encode(duration)
        #expect(try JSONDecoder().decode(CookingDuration.self, from: data) == duration)
    }
}
