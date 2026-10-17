import Foundation
import Testing
@testable import Scheduler

@Suite("Backward list scheduling")
struct SchedulerTests {
    let seating = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func singleTaskEndsAtDeadline() throws {
        let roast = SchedulableTask(name: "Roast", duration: .seconds(90 * 60))
        let placements = try Scheduler.schedule(SchedulingProblem(tasks: [roast], deadline: seating))
        #expect(placements.count == 1)
        #expect(placements[0].end == seating)
        #expect(placements[0].start == seating.addingTimeInterval(-90 * 60))
    }

    @Test func dependencyFinishesBeforeDependentStarts() throws {
        let dough = SchedulableTask(name: "Make dough", duration: .seconds(20 * 60))
        let rest = SchedulableTask(name: "Rest dough", duration: .seconds(24 * 3600), kind: .passive, dependencies: [dough.id])
        let bake = SchedulableTask(name: "Bake", duration: .seconds(45 * 60), dependencies: [rest.id])
        let placements = try Scheduler.schedule(SchedulingProblem(tasks: [bake, dough, rest], deadline: seating))
        let byID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
        #expect(byID[bake.id]?.end == seating)
        #expect(byID[rest.id]!.end <= byID[bake.id]!.start)
        #expect(byID[dough.id]!.end <= byID[rest.id]!.start)
    }

    @Test func detectsCycles() {
        let a = TaskID(), b = TaskID()
        let tasks = [
            SchedulableTask(id: a, name: "A", duration: .seconds(60), dependencies: [b]),
            SchedulableTask(id: b, name: "B", duration: .seconds(60), dependencies: [a]),
        ]
        #expect(throws: SchedulingError.cycle) {
            try Scheduler.schedule(SchedulingProblem(tasks: tasks, deadline: seating))
        }
    }

    @Test func rejectsUnknownDependencies() {
        let ghost = TaskID()
        let task = SchedulableTask(name: "A", duration: .seconds(60), dependencies: [ghost])
        #expect(throws: SchedulingError.unknownDependency(ghost)) {
            try Scheduler.schedule(SchedulingProblem(tasks: [task], deadline: seating))
        }
    }
}
