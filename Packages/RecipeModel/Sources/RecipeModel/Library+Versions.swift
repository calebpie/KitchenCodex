import Foundation

// Conveniences over the library models. No stored properties: these read and write the schema v1
// fields and relationships only.

extension RecipeSchemaV1.Recipe {
    /// Versions, oldest first.
    public var sortedVersions: [RecipeVersion] {
        (versions ?? []).sorted { $0.versionNumber < $1.versionNumber }
    }

    public var nextVersionNumber: Int {
        (versions ?? []).map(\.versionNumber).max().map { $0 + 1 } ?? 1
    }

    /// Adds `version` as the newest snapshot and makes it current. Earlier versions stay as history.
    /// Both models must already be in the same context.
    public func addVersion(_ version: RecipeVersion) {
        version.versionNumber = nextVersionNumber
        versions = (versions ?? []) + [version]
        currentVersion = version
        updatedAt = .now
    }

    /// The cover photo: the newest image with the `.photo` role. Page scans and cook photos are never covers.
    public var coverImage: RecipeImage? {
        (images ?? []).filter { $0.role == .photo }.max { $0.createdAt < $1.createdAt }
    }

    public var cookCount: Int { cookSessions?.count ?? 0 }
    public var isNeverCooked: Bool { cookCount == 0 }
}

extension RecipeSchemaV1.RecipeVersion {
    public var sortedIngredients: [Ingredient] {
        (ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    public var sortedSteps: [Step] {
        (steps ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Total time as written, or prep plus cook when only those are given.
    public var displayMinutes: Int? {
        if let totalMinutes { return totalMinutes }
        switch (prepMinutes, cookMinutes) {
        case (nil, nil): return nil
        case let (prep, cook): return (prep ?? 0) + (cook ?? 0)
        }
    }
}
