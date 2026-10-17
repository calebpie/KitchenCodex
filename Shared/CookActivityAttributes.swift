#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity payload for a cook or service session (02 §1.2). Compiled into both the app
/// and the widget extension so the two agree on the shape.
struct CookActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentStep: String
        var nextStep: String?
        /// When the soonest running timer ends, if any.
        var timerEnd: Date?
    }

    var recipeTitle: String
    var sessionID: UUID
}
#endif
