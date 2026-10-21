import Capture
import Foundation

/// The parts the cook chose on Split into N recipes (04 §5.1 "Sub-recipes on one page", ux-notes
/// row 61), by their ingredient group's heading, with the title each takes. Kept by heading so an
/// edit made after the sheet still finds its part when the plan is drawn again at Save.
struct SplitChoice: Equatable {
    var titles: [String: String]

    /// The plan's parts this choice takes, by index.
    func chosen(in plan: ComponentSplit.Plan) -> Set<Int> {
        Set(plan.parts.indices.filter { titles[plan.parts[$0].group] != nil })
    }
}
