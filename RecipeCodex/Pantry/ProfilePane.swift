import Capture
import Intelligence
import RecipeModel
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import Units

/// Pantry → Profile (03 §3.17): how you cook, how you like amounts shown, the kitchen theme, which
/// model plans menus, and exporting the library. Voice and hands-free join with cook mode (Phase 3);
/// until then the row is hidden, and `UserProfile.voiceCommandsEnabled` waits in the model.
struct ProfilePane: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\UserProfile.createdAt)]) private var profiles: [UserProfile]

    var body: some View {
        if let profile = profiles.first {
            ProfileForm(profile: profile)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { _ = UserProfile.current(in: modelContext) }
        }
    }
}

private struct ProfileForm: View {
    @Bindable var profile: UserProfile

    @Query(sort: [SortDescriptor(\Recipe.title, comparator: .localizedStandard)]) private var recipes: [Recipe]

    var body: some View {
        Form {
            Section {
                Picker("Proficiency", selection: $profile.proficiency) {
                    ForEach(Proficiency.allCases, id: \.self) { level in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.title)
                            Text(level.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Proficiency")
            } footer: {
                Text("The schedule scales its time estimates to how you cook, and gives you as many hands-on tasks at once as your level handles.")
            }

            Section {
                // Two options each: segmented, so the choice is visible without opening a menu.
                LabeledContent("Measurements") {
                    Picker("Measurements", selection: $profile.unitPreference) {
                        Text("US").tag(UnitPreference.us)
                        Text("Metric").tag(UnitPreference.metric)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                LabeledContent("Temperature") {
                    Picker("Temperature", selection: $profile.temperaturePreference) {
                        Text("°F").tag(TemperaturePreference.fahrenheit)
                        Text("°C").tag(TemperaturePreference.celsius)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            } header: {
                Text("Units")
            } footer: {
                Text("Recipes show amounts written in the other system converted to yours, rounded to what you can measure; with US, grams and kilograms stay as written so precise recipes keep their weights. Temperatures are shown in your unit. A recipe's More menu has Units, to convert every amount and temperature or show them as written for that reading. Tap a temperature, or touch and hold an ingredient, to see it as written.")
            }

            Section {
                Toggle("Kitchen Theme", isOn: $profile.kitchenThemeEnabled)
            } footer: {
                Text("High contrast, larger step type and solid backgrounds behind text, in cook mode. It applies once cook mode arrives in a later version; it is never turned on automatically.")
            }

            Section {
                Picker("Menus and Pairings", selection: $profile.heavyReasoningModel) {
                    Text("Apple cloud model").tag(ModelTier.appleCloud.rawValue)
                    Text("Claude").tag(ModelTier.claude.rawValue)
                }
            } header: {
                Text("Intelligence")
            } footer: {
                Text("Planning a menu and suggesting pairings use Apple's cloud model unless you choose Claude. Reading recipes you import always stays on this device.")
            }

            Section {
                ShareLink(item: LibraryExport(recipes: recipes.map(ExportRecipe.init(recipe:))), preview: SharePreview("Recipe Codex Library", icon: Image(systemName: "books.vertical"))) {
                    Label("Export Library", systemImage: "square.and.arrow.up")
                }
                .disabled(recipes.isEmpty)
            } header: {
                Text("Export")
            } footer: {
                Text(recipes.isEmpty
                    ? "Add a recipe to export your library."
                    : "A Markdown file for each of your \(recipes.count) recipes, in one .zip archive, as written.")
            }
        }
    }
}

/// Profile → Export Library: one Markdown file per recipe (`RecipeExporter`), zipped into
/// "Recipe Codex Library.zip" when the share sheet asks for it. The zip comes from
/// `NSFileCoordinator`'s `.forUploading` reading of a folder, which archives it with no code of ours.
struct LibraryExport: Transferable {
    let recipes: [ExportRecipe]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { export in
            SentTransferredFile(try export.archive())
        }
        .suggestedFileName("Recipe Codex Library.zip")
    }

    /// Writes the files into a fresh folder and returns the zip of it, in the temporary directory.
    /// Off the main actor: the share sheet asks for the file and waits.
    nonisolated func archive() throws -> URL {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appending(path: "LibraryExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let folder = work.appending(path: "Recipe Codex Library", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, recipe) in zip(Self.fileNames(for: recipes), recipes) {
            try Data(RecipeExporter.markdown(recipe).utf8).write(to: folder.appending(path: name))
        }

        var coordinatorError: NSError?
        var zipped: URL?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { temporaryZip in
            // The coordinator removes its zip when this block returns, so keep a copy.
            let destination = work.appending(path: "Recipe Codex Library.zip")
            do {
                try fileManager.copyItem(at: temporaryZip, to: destination)
                zipped = destination
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError { throw error }
        guard let zipped else { throw CocoaError(.fileWriteUnknown) }
        return zipped
    }

    /// One file name per recipe, its title made safe; repeats get " 2", " 3".
    nonisolated static func fileNames(for recipes: [ExportRecipe]) -> [String] {
        var used: Set<String> = []
        return recipes.map { recipe in
            let base = (RecipeExporter.fileName(for: recipe.title, extension: "md") as NSString).deletingPathExtension
            var name = "\(base).md"
            var number = 2
            while used.contains(name.lowercased()) {
                name = "\(base) \(number).md"
                number += 1
            }
            used.insert(name.lowercased())
            return name
        }
    }
}

extension Proficiency {
    var title: String {
        switch self {
        case .learning: "Learning"
        case .confident: "Confident"
        case .advanced: "Advanced"
        case .expert: "Expert"
        }
    }

    /// One sentence each (03 §3.17, 04 §5.1 Proficiency).
    var explanation: String {
        switch self {
        case .learning: "You follow recipes closely. The schedule allows extra time for prep and technique."
        case .confident: "You're at home with most recipes. Times are taken as the recipe gives them."
        case .advanced: "Fast hands and a feel for timing. The schedule tightens the estimates."
        case .expert: "You run several dishes at once and know when to check the oven without a timer. The schedule packs hands-on tasks tightly and trusts your timing."
        }
    }
}

extension UnitPreference {
    /// The Units package's system for this preference.
    var measurementSystem: MeasurementSystem {
        switch self {
        case .us: .us
        case .metric: .metric
        }
    }
}
