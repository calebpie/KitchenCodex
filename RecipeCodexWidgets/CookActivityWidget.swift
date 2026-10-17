import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity for an active cook or service session: Dynamic Island, Lock Screen, StandBy
/// and the Watch Smart Stack. Layout is a placeholder until Phase 3's cook mode drives it.
struct CookActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.recipeTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(context.state.currentStep)
                    .font(.headline)
                    .lineLimit(2)
                if let end = context.state.timerEnd {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.title3.monospacedDigit())
                }
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "frying.pan")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.currentStep)
                        .lineLimit(2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let end = context.state.timerEnd {
                        Text(timerInterval: Date.now...end, countsDown: true)
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: "frying.pan")
            } compactTrailing: {
                if let end = context.state.timerEnd {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 48)
                }
            } minimal: {
                Image(systemName: "frying.pan")
            }
        }
    }
}
