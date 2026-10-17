import SwiftUI
import WidgetKit

/// "Tonight's plan" home-screen widget (02 §1.2). Placeholder content until Phase 4 has events.
struct TonightEntry: TimelineEntry {
    let date: Date
    let headline: String
}

struct TonightProvider: TimelineProvider {
    func placeholder(in context: Context) -> TonightEntry {
        TonightEntry(date: .now, headline: "Nothing planned tonight")
    }

    func getSnapshot(in context: Context, completion: @escaping (TonightEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TonightEntry>) -> Void) {
        let entry = placeholder(in: context)
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct TonightWidgetView: View {
    var entry: TonightEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tonight", systemImage: "frying.pan")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.headline)
                .font(.headline)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TonightWidget: Widget {
    let kind = "com.calebpietrafesa.RecipeCodex.Tonight"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TonightProvider()) { entry in
            TonightWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tonight")
        .description("What you're cooking tonight and the next thing to do.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    TonightWidget()
} timeline: {
    TonightEntry(date: .now, headline: "Nothing planned tonight")
}
