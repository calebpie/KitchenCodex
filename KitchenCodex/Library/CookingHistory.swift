import RecipeModel
import SwiftData
import SwiftUI

// Cooking history (04 §5.1 "Cooked chip", ux-notes row 54): the times a recipe was cooked, and the
// cooks from before the app, added by hand. A past cook is a `CookSession` with `endedAt` set and no
// event, so one of them turns "Never cooked" into the cooked state; cook mode (Phase 3) adds the rest.

extension CookSession {
    /// When it was cooked: the end for a finished cook, else the start.
    var cookedOn: Date { endedAt ?? startedAt }
}

extension Recipe {
    /// Cook sessions, most recent first.
    var sortedCookSessions: [CookSession] {
        (cookSessions ?? []).sorted { $0.cookedOn > $1.cookedOn }
    }

    /// The detail's chip: "Never cooked", "Cooked · Oct 2", "Cooked 3 times".
    var cookedChipTitle: String {
        switch cookCount {
        case 0: "Never cooked"
        case 1: "Cooked · \(sortedCookSessions[0].cookedOn.formatted(.dateTime.month(.abbreviated).day()))"
        default: "Cooked \(cookCount) times"
        }
    }
}

/// Detail's cooked state as a chip; the button around it opens Cooking History.
struct CookedChip: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 4) {
            if !recipe.isNeverCooked {
                Image(systemName: "checkmark.circle")
                    .imageScale(.small)
            }
            Text(recipe.cookedChipTitle)
            Image(systemName: "chevron.forward")
                .imageScale(.small)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.fill.tertiary, in: .capsule)
        .contentShape(.capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recipe.cookedChipTitle)
    }
}

/// The Cooking History sheet: each cook with its date, place and rating, Add Past Cook, and swipe to
/// delete. Opened from detail's cooked chip and the editor's Cooked Before row.
struct CookingHistoryView: View {
    let recipe: Recipe

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isAddingPastCook = false

    var body: some View {
        NavigationStack {
            List {
                let sessions = recipe.sortedCookSessions
                if sessions.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("Never Cooked", systemImage: "frying.pan")
                        } description: {
                            Text("Cooked it before? Add a past cook with its date, and a rating if you like.")
                        }
                    }
                } else {
                    Section {
                        ForEach(sessions) { session in
                            CookSessionRow(session: session)
                        }
                        .onDelete { offsets in
                            for offset in offsets { modelContext.delete(sessions[offset]) }
                            recipe.updatedAt = .now
                            try? modelContext.save()
                        }
                    } header: {
                        Text(sessions.count == 1 ? "1 Cook" : "\(sessions.count) Cooks")
                    }
                }
                Section {
                    Button("Add Past Cook", systemImage: "plus.circle") { isAddingPastCook = true }
                }
            }
            .navigationTitle("Cooking History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .sheet(isPresented: $isAddingPastCook) {
                PastCookForm(recipe: recipe)
            }
        }
    }
}

/// One cook: the date, where, the rating and the note.
private struct CookSessionRow: View {
    let session: CookSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.cookedOn.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                Spacer()
                if let rating = session.rating {
                    RatingStars(rating: rating)
                }
            }
            let details = [session.placeName, session.event?.name].compactMap { $0?.isEmpty == false ? $0 : nil }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Filled and empty stars for a rating out of five.
private struct RatingStars: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .imageScale(.small)
                    .foregroundStyle(star <= rating ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(rating == 1 ? "1 star" : "\(rating) stars")
    }
}

/// Add Past Cook: a date (today unless changed, never in the future), an optional rating and note.
private struct PastCookForm: View {
    let recipe: Recipe

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var date = Date.now
    @State private var rating: Int?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section {
                    HStack(spacing: 14) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                // Tapping the rating again clears it.
                                rating = rating == star ? nil : star
                            } label: {
                                Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                                    .font(.title3)
                                    .foregroundStyle(star <= (rating ?? 0) ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                                    .frame(minWidth: 36, minHeight: 36)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(star == 1 ? "1 star" : "\(star) stars")
                            .accessibilityAddTraits(rating == star ? .isSelected : [])
                        }
                    }
                } header: {
                    Text("Rating")
                } footer: {
                    Text("Optional.")
                }
                Section("Note") {
                    TextField("How it went, what you'd change", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Past Cook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm) { add() }
                }
            }
        }
    }

    private func add() {
        let session = CookSession(startedAt: date)
        modelContext.insert(session)
        session.endedAt = date
        session.rating = rating
        session.notes = note.trimmed
        session.recipe = recipe
        recipe.updatedAt = .now
        try? modelContext.save()
        dismiss()
    }
}
