import Foundation
import SwiftData

extension RecipeSchemaV1.UserProfile {
    /// The cook's one profile, created on first use. CloudKit can bring a second record from another
    /// device before the two have met; the oldest wins so every device settles on the same one.
    public static func current(in context: ModelContext) -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        if let profile = try? context.fetch(descriptor).first { return profile }
        let profile = UserProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }
}
