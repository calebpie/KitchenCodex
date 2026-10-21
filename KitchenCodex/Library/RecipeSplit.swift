import Capture
import Foundation
import RecipeModel
import SwiftData
import SwiftUI

// Split into N recipes (04 §2 Phase 2, §5.1 "Sub-recipes on one page"; ux-notes row 61): a recipe
// whose ingredient groups and step groups line up is offered as a parent and its component recipes,
// always on the cook's word. The parent keeps its title, headnote, cover and whatever no component
// takes, and gains a component link to each; each component carries its group's ingredient lines
// and steps, whole and in order, titled from the group. Nothing is renumbered, no step is split or
// merged. Cook-time inlining is Phase 3.

/// The parts the cook chose on the split sheet, by their ingredient group's heading, with the title
/// each takes. Kept by heading so an edit made after the sheet still finds its part when the plan
/// is drawn again at Save.
struct SplitChoice: Equatable {
    var titles: [String: String]

    /// The plan's parts this choice takes, by index.
    func chosen(in plan: ComponentSplit.Plan) -> Set<Int> {
        Set(plan.parts.indices.filter { titles[plan.parts[$0].group] != nil })
    }

    /// The parts the plan makes components to begin with.
    static func defaults(for plan: ComponentSplit.Plan) -> SplitChoice {
        SplitChoice(titles: Dictionary(plan.parts.filter(\.isComponent).map { ($0.group, $0.title) }, uniquingKeysWith: { first, _ in first }))
    }
}

/// The sheet that confirms a split: each part with its ingredient and step counts, a switch that
/// makes it a recipe of its own, and its title; what stays with the parent; Split.
struct SplitSheet: View {
    /// The parent's title.
    let title: String
    let plan: ComponentSplit.Plan
    var initial: SplitChoice?
    var onSplit: (SplitChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<Int> = []
    @State private var titles: [Int: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("“\(title)” keeps its title, headnote and photo and links each recipe made from it. Steps stay as written: none is split or merged.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(plan.parts) { part in
                    Section {
                        Toggle(isOn: Binding { chosen.contains(part.id) } set: { if $0 { chosen.insert(part.id) } else { chosen.remove(part.id) } }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.group)
                                Text(counts(ingredients: part.ingredients.count, steps: part.steps.count))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if chosen.contains(part.id) {
                            TextField("Title", text: Binding { titles[part.id] ?? part.title } set: { titles[part.id] = $0 })
                                .font(.headline)
                        }
                    } footer: {
                        if !part.isComponent, !chosen.contains(part.id) {
                            Text("Stays in “\(title)” unless you make it a recipe.")
                        }
                    }
                }
                Section("Stays in “\(title)”") {
                    let kept = plan.parent(choosing: chosen)
                    Text(counts(ingredients: kept.ingredients.count, steps: kept.steps.count))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(chosen.isEmpty ? "Split" : "Split into \(chosen.count + 1) Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split", role: .confirm) {
                        let choice = SplitChoice(titles: Dictionary(chosen.sorted().map { index in
                            let part = plan.parts[index]
                            let title = (titles[index] ?? part.title).trimmed
                            return (part.group, title.isEmpty ? part.title : title)
                        }, uniquingKeysWith: { first, _ in first }))
                        onSplit(choice)
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
            }
            .onAppear {
                let start = initial ?? SplitChoice.defaults(for: plan)
                chosen = start.chosen(in: plan)
                for index in chosen { titles[index] = start.titles[plan.parts[index].group] }
            }
        }
    }

    private func counts(ingredients: Int, steps: Int) -> String {
        "\(ingredients == 1 ? "1 ingredient" : "\(ingredients) ingredients") · \(steps == 1 ? "1 step" : "\(steps) steps")"
    }
}

/// The offer and, once confirmed, what Save will do: "Split into 3 Recipes…", or "Saves as 3
/// recipes: …" with Don't Split.
struct SplitOfferRow: View {
    let plan: ComponentSplit.Plan
    let split: SplitChoice?
    var onOffer: () -> Void
    var onCancel: () -> Void

    var body: some View {
        if let split, !split.chosen(in: plan).isEmpty {
            let names = plan.parts.indices.filter(split.chosen(in: plan).contains).compactMap { split.titles[plan.parts[$0].group] }
            VStack(alignment: .leading, spacing: 8) {
                Label("Saves as \(names.count + 1) recipes, with \(ListFormatter.localizedString(byJoining: names.map { "“\($0)”" })) linked as components.", systemImage: "square.split.2x1")
                    .font(.subheadline)
                HStack(spacing: 16) {
                    Button("Change…", action: onOffer)
                    Button("Don't Split", role: .destructive, action: onCancel)
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
        } else {
            Button(action: onOffer) {
                Label("Split into \(plan.defaultRecipeCount) Recipes…", systemImage: "square.split.2x1")
            }
            .accessibilityHint("Makes its components recipes of their own, linked from this one. Asks first.")
        }
    }
}

@MainActor
enum RecipeSplitting {
    /// The parent gains a component link to each part, in order.
    static func link(_ parent: Recipe, to components: [Recipe], in context: ModelContext) {
        for component in components {
            CrossReferenceLinking.link(parent, to: component, phrase: "", in: context)
        }
        try? context.save()
    }

    // MARK: - From the web import preview

    /// The plan the preview's draft allows: its ingredient lines under their headings and its
    /// steps, with the page's named sections while the steps are the page's own.
    static func plan(for draft: RecipeDraft, imported: ImportedRecipe?) -> ComponentSplit.Plan? {
        let lines = draft.groupedIngredients
        let steps = StepSplitter.steps(from: draft.stepsText)
        let sections = imported.flatMap { steps == $0.steps.map(\.text) ? $0.stepGroups : nil } ?? [:]
        return ComponentSplit.plan(title: draft.title, ingredientGroups: lines.map(\.group), steps: steps, stepGroups: sections)
    }

    /// Saves the preview as a parent and its chosen components, each through `saveImport` with the
    /// page's source; each component's step photos go with its steps. Nil when the choice no longer
    /// finds a part (the preview was edited since), so the caller saves one recipe.
    static func saveImport(_ draft: RecipeDraft, imported: ImportedRecipe, choice: SplitChoice, in context: ModelContext) -> Recipe? {
        guard let plan = plan(for: draft, imported: imported) else { return nil }
        let chosen = choice.chosen(in: plan)
        guard !chosen.isEmpty else { return nil }
        let lines = draft.groupedIngredients
        let steps = StepSplitter.steps(from: draft.stepsText)
        let kept = plan.parent(choosing: chosen)

        /// The import with only these steps, so step photos follow their steps.
        func importedKeeping(_ indices: [Int]) -> ImportedRecipe {
            func key(_ text: String) -> String { text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            var part = imported
            let texts = Set(indices.map { key(steps[$0]) })
            part.steps = imported.steps.filter { texts.contains(key($0.text)) }
            part.stepGroups = [:]
            return part
        }

        var parentDraft = draft
        parentDraft.ingredientsText = RecipeDraft.ingredientsText(kept.ingredients.map { (lines[$0].group, lines[$0].parsed.rawText) })
        parentDraft.stepsText = kept.steps.map { steps[$0] }.joined(separator: "\n\n")
        let parent = parentDraft.saveImport(importedKeeping(kept.steps), in: context)

        var components: [Recipe] = []
        for index in chosen.sorted() {
            let part = plan.parts[index]
            var componentDraft = RecipeDraft()
            componentDraft.title = choice.titles[part.group] ?? part.title
            componentDraft.ingredientsText = RecipeDraft.ingredientsText(part.ingredients.map { (nil, lines[$0].parsed.rawText) })
            componentDraft.stepsText = part.steps.map { steps[$0] }.joined(separator: "\n\n")
            componentDraft.changeSummary = "Split from “\(parent.title)”"
            var componentImport = importedKeeping(part.steps)
            componentImport.title = componentDraft.title
            componentImport.headnote = nil
            componentImport.notes = []
            componentImport.imageURL = nil
            componentImport.imageData = nil
            components.append(componentDraft.saveImport(componentImport, in: context))
        }
        link(parent, to: components, in: context)
        return parent
    }

    // MARK: - From scan review

    /// The plan a reviewed recipe's items allow.
    static func plan(for review: ReviewRecipe) -> ComponentSplit.Plan? {
        ComponentSplit.plan(title: review.title?.text ?? "", ingredientGroups: review.ingredients.map(\.group), steps: review.steps.map(\.text))
    }

    /// A reviewed recipe as the parent and its chosen components, each a review of its own items:
    /// the parent keeps the title, yield, headnote, notes, cover and course with what no component
    /// takes; a component has its group's lines (no heading, the group being the recipe), its steps
    /// and their printed step photos, and the pointers its text carries. Nil when the choice finds
    /// no part.
    static func split(_ review: ReviewRecipe) -> (parent: ReviewRecipe, components: [ReviewRecipe])? {
        guard let choice = review.split, let plan = plan(for: review) else { return nil }
        let chosen = choice.chosen(in: plan)
        guard !chosen.isEmpty else { return nil }
        let kept = plan.parent(choosing: chosen)

        func pointers(in items: [ReviewItem]) -> [ReviewPointer] {
            review.pointers.filter { pointer in items.contains { $0.text.localizedCaseInsensitiveContains(pointer.reference.phrase.trimmingCharacters(in: CharacterSet(charactersIn: "()"))) } }
        }

        var parent = review
        parent.ingredients = kept.ingredients.map { review.ingredients[$0] }
        parent.steps = kept.steps.map { review.steps[$0] }
        parent.stepPhotos = review.stepPhotos.filter { photo in parent.steps.contains { $0.id == photo.value } }
        parent.split = nil
        // A pointer stays with the parent when its words are in what the parent keeps, or in nothing.
        let parentPointers = pointers(in: parent.allItems), anywhere = pointers(in: review.allItems)
        parent.pointers = review.pointers.filter { parentPointers.contains($0) || !anywhere.contains($0) }

        let components = chosen.sorted().map { index -> ReviewRecipe in
            let part = plan.parts[index]
            var component = ReviewRecipe()
            component.title = ReviewItem(text: choice.titles[part.group] ?? part.title, regions: [])
            component.ingredients = part.ingredients.map { var item = review.ingredients[$0]; item.group = nil; return item }
            component.steps = part.steps.map { review.steps[$0] }
            component.stepPhotos = review.stepPhotos.filter { photo in component.steps.contains { $0.id == photo.value } }
            component.layoutSignature = review.layoutSignature
            component.confidence = review.confidence
            component.method = review.method
            component.pointers = pointers(in: component.ingredients + component.steps)
            return component
        }
        return (parent, components)
    }
}
