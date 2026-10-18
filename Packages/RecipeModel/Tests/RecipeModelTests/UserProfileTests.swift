import Foundation
import SwiftData
import Testing
@testable import RecipeModel

@Suite("User profile")
struct UserProfileTests {
    @Test func defaultsToUSAndFahrenheit() {
        let profile = UserProfile()
        #expect(profile.unitPreference == .us)
        #expect(profile.temperaturePreference == .fahrenheit)
        #expect(profile.proficiency == .confident)
        #expect(profile.concurrencyLimit == 2)
    }

    /// 04 §5.1 Proficiency: four tiers, and hands-on concurrency follows the tier.
    @Test func concurrencyFollowsTheTier() {
        #expect(Proficiency.allCases == [.learning, .confident, .advanced, .expert])
        let profile = UserProfile(proficiency: .learning)
        #expect(profile.concurrencyLimit == 1)
        profile.proficiency = .advanced
        #expect(profile.concurrencyLimit == 3)
        profile.proficiency = .expert
        #expect(profile.concurrencyLimit == 4)
    }

    @Test func concurrencyIsNotStored() {
        let attributes = RecipeStore.schema.entities.first { $0.name == "UserProfile" }?.attributes.map(\.name) ?? []
        #expect(attributes.contains("proficiency"))
        #expect(!attributes.contains("concurrencyLimit"))
    }

    @Test func currentCreatesOnceAndKeepsChanges() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let first = UserProfile.current(in: context)
        first.unitPreference = .metric
        first.temperaturePreference = .celsius
        try context.save()

        let again = UserProfile.current(in: context)
        #expect(again.id == first.id)
        #expect(again.unitPreference == .metric)
        #expect(again.temperaturePreference == .celsius)
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 1)
    }

    /// Two devices can each create a profile before syncing; both settle on the older one.
    @Test func currentPrefersTheOldestOfDuplicates() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let newer = UserProfile(proficiency: .learning)
        let older = UserProfile(proficiency: .advanced)
        older.createdAt = .now.addingTimeInterval(-3_600)
        context.insert(newer)
        context.insert(older)
        try context.save()

        #expect(UserProfile.current(in: context).id == older.id)
    }
}
