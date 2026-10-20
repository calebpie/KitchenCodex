import Capture
import RecipeModel
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Recipes → More → Import Library…: brings in a Paprika (`.paprikarecipes`) or Mela
/// (`.melarecipes`, `.melarecipe`) export through the same save path as a web import. Shows progress
/// with counts, skips recipes already in the library (same title and source link), and reports
/// what was added, skipped and unreadable.
struct LibraryImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    enum Phase: Equatable {
        case choosing
        case reading(String)
        case importing(done: Int, total: Int, appName: String)
        case finished(Summary)
        case failed(String)
    }

    struct Summary: Equatable {
        var appName: String
        var added = 0
        var skipped = 0
        var unreadable = 0
        var stopped = false
    }

    @State private var phase: Phase = .choosing
    @State private var isChoosingFile = false
    @State private var work: Task<Void, Never>?

    /// The four export extensions (dynamic types, since no app here declares them), plus ZIP and
    /// JSON for exports that were renamed.
    static let contentTypes: [UTType] = LibraryFormat.allFileExtensions.compactMap { UTType(filenameExtension: $0, conformingTo: .data) } + [.zip, .json]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import Library")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // Escape stops an import, cancels the sheet, or closes the summary (03 §4,
                        // ux-notes row 43).
                        if isImporting {
                            Button("Stop", role: .cancel) { work?.cancel() }
                                .keyboardShortcut(.cancelAction)
                        } else if !isFinished {
                            Button(role: .cancel) { dismiss() }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isFinished {
                            Button("Done", role: .confirm) { dismiss() }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
                }
        }
        .interactiveDismissDisabled(isImporting)
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: Self.contentTypes) { result in
            switch result {
            case let .success(url):
                work = Task { await importLibrary(from: url) }
            case let .failure(error):
                phase = .failed(error.localizedDescription)
            }
        }
        .onAppear {
            if phase == .choosing { isChoosingFile = true }
        }
        .onDisappear { work?.cancel() }
    }

    private var isImporting: Bool {
        switch phase {
        case .reading, .importing: true
        default: false
        }
    }

    private var isFinished: Bool {
        if case .finished = phase { true } else { false }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .choosing:
            ContentUnavailableView {
                Label("Import a Library", systemImage: "tray.and.arrow.down")
            } description: {
                Text("Choose an export from Paprika (.paprikarecipes) or Mela (.melarecipes). Recipes already in your library are skipped.")
            } actions: {
                Button("Choose File…") { isChoosingFile = true }
                    .buttonStyle(.borderedProminent)
            }
        case let .reading(name):
            VStack(spacing: 12) {
                ProgressView()
                Text("Opening “\(name)”…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .importing(done, total, appName):
            VStack(spacing: 16) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .frame(maxWidth: 320)
                Text("Importing \(min(done + 1, total)) of \(total) from \(appName)…")
                    .font(.subheadline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.default, value: done)
        case let .finished(summary):
            ContentUnavailableView {
                Label(summary.added == 0 ? "Nothing New to Import" : "Library Imported", systemImage: summary.added == 0 ? "checkmark.circle" : "tray.full")
            } description: {
                Text(Self.report(summary))
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't Import", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Choose Another File…") { isChoosingFile = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    /// "Added 12 recipes from Paprika. Skipped 3 already in your library. 1 couldn't be read.", or
    /// "All 3 recipes are already in your library." when nothing was new.
    static func report(_ summary: Summary) -> String {
        func recipes(_ count: Int) -> String { count == 1 ? "1 recipe" : "\(count) recipes" }
        var sentences: [String] = []
        if summary.added > 0 || summary.skipped == 0 {
            sentences.append("Added \(recipes(summary.added)) from \(summary.appName).")
            if summary.skipped > 0 { sentences.append("Skipped \(summary.skipped) already in your library.") }
        } else {
            sentences.append(summary.skipped == 1 ? "The recipe is already in your library." : "All \(summary.skipped) recipes are already in your library.")
        }
        if summary.unreadable > 0 { sentences.append("\(summary.unreadable) couldn't be read.") }
        if summary.stopped { sentences.append("Stopped before the end; run the import again to add the rest.") }
        return sentences.joined(separator: " ")
    }

    // MARK: - Importing

    private func importLibrary(from url: URL) async {
        phase = .reading(url.lastPathComponent)
        let library: LibraryArchive
        do {
            library = try await Self.open(url)
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return
        }

        var summary = Summary(appName: library.format.appName)
        var known = existingKeys()
        for index in 0..<library.count {
            if Task.isCancelled {
                summary.stopped = true
                break
            }
            phase = .importing(done: index, total: library.count, appName: summary.appName)
            guard var recipe = await Self.read(library, at: index) else {
                summary.unreadable += 1
                continue
            }
            let key = Self.duplicateKey(title: recipe.title, url: recipe.sourceURL)
            guard !known.contains(key) else {
                summary.skipped += 1
                continue
            }
            // Only the photo the export carries; a library import doesn't fetch hundreds of covers.
            recipe.imageURL = nil
            var draft = RecipeDraft(imported: recipe)
            if recipe.imageData != nil {
                draft.photo = await RecipeDraft.coverPhoto(for: recipe).change
            }
            draft.saveImport(recipe, in: modelContext)
            known.insert(key)
            summary.added += 1
        }
        phase = .finished(summary)
    }

    /// Reading a large export takes a moment; keep it off the main actor.
    @concurrent
    nonisolated private static func open(_ url: URL) async throws -> LibraryArchive {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try LibraryArchive(data: data, fileName: url.lastPathComponent)
    }

    @concurrent
    nonisolated private static func read(_ library: LibraryArchive, at index: Int) async -> ImportedRecipe? {
        try? library.recipe(at: index)
    }

    /// Title and source link of every recipe already saved.
    private func existingKeys() -> Set<String> {
        let recipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []
        return Set(recipes.map { Self.duplicateKey(title: $0.title, url: $0.source?.url) })
    }

    /// An exact duplicate has the same title (ignoring case and surrounding spaces) and source link.
    nonisolated static func duplicateKey(title: String, url: URL?) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "\n" + (url?.absoluteString ?? "")
    }
}
