import Foundation
import KnowledgeBase

/// Identifies a task inside one scheduling problem.
public struct TaskID: Hashable, Sendable, Codable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Whether the cook's hands are needed. Passive tasks (resting, chilling, oven time)
/// may overlap each other and active work.
public enum TaskKind: String, Sendable, Codable {
    case active, passive
}

/// One unit of work the scheduler places on the timeline.
public struct SchedulableTask: Sendable, Equatable, Identifiable {
    public let id: TaskID
    public var name: String
    public var duration: Duration
    public var kind: TaskKind
    /// Tasks that must finish before this one starts.
    public var dependencies: Set<TaskID>
    /// The component type, used to apply a hold rule between this task and its dependents.
    public var component: ComponentType?

    public init(
        id: TaskID = TaskID(),
        name: String,
        duration: Duration,
        kind: TaskKind = .active,
        dependencies: Set<TaskID> = [],
        component: ComponentType? = nil
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.kind = kind
        self.dependencies = dependencies
        self.component = component
    }
}

/// A menu's worth of tasks and the moment everything must be done.
public struct SchedulingProblem: Sendable {
    public var tasks: [SchedulableTask]
    public var deadline: Date
    /// How many active tasks the cook can run at once. Phase 5 enforces it; Phase 0 records it.
    public var concurrencyLimit: Int

    public init(tasks: [SchedulableTask], deadline: Date, concurrencyLimit: Int = 2) {
        self.tasks = tasks
        self.deadline = deadline
        self.concurrencyLimit = concurrencyLimit
    }
}

/// Where a task landed.
public struct Placement: Sendable, Equatable, Identifiable {
    public var id: TaskID
    public var start: Date
    public var end: Date
}

public enum SchedulingError: Error, Equatable {
    case cycle
    case unknownDependency(TaskID)
}

/// Backward list scheduling: start at the deadline and walk dependencies backwards so each
/// task ends no later than the earliest start of anything that depends on it.
///
/// Phase 0 ships the dependency-respecting skeleton. Phase 5 adds the concurrency limit,
/// hold rules, host-presence objective and explanations.
public enum Scheduler {
    public static func schedule(_ problem: SchedulingProblem) throws -> [Placement] {
        let byID = Dictionary(uniqueKeysWithValues: problem.tasks.map { ($0.id, $0) })
        for task in problem.tasks {
            for dep in task.dependencies where byID[dep] == nil {
                throw SchedulingError.unknownDependency(dep)
            }
        }

        // Dependents of each task, so we can find the earliest start among them.
        var dependents: [TaskID: [TaskID]] = [:]
        for task in problem.tasks {
            for dep in task.dependencies {
                dependents[dep, default: []].append(task.id)
            }
        }

        // Reverse topological order: tasks with no dependents first (Kahn's algorithm on the reversed graph).
        var remainingDependents = dependents.mapValues(\.count)
        var ready = problem.tasks.filter { (remainingDependents[$0.id] ?? 0) == 0 }.map(\.id)
        var order: [TaskID] = []
        while let id = ready.popLast() {
            order.append(id)
            for dep in byID[id]!.dependencies {
                remainingDependents[dep]! -= 1
                if remainingDependents[dep] == 0 { ready.append(dep) }
            }
        }
        guard order.count == problem.tasks.count else { throw SchedulingError.cycle }

        var placements: [TaskID: Placement] = [:]
        for id in order {
            let task = byID[id]!
            let latestEnd = (dependents[id] ?? []).compactMap { placements[$0]?.start }.min() ?? problem.deadline
            let seconds = TimeInterval(task.duration.components.seconds)
            placements[id] = Placement(id: id, start: latestEnd.addingTimeInterval(-seconds), end: latestEnd)
        }
        return problem.tasks.compactMap { placements[$0.id] }
    }
}
