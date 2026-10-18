import RecipeModel
import SwiftData
import SwiftUI
import Units

/// Pantry → Profile (03 §3.17): how you cook and how you like amounts shown. Voice, the kitchen
/// theme and intelligence settings join this pane with the features they control.
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
                Text("The schedule scales its time estimates to how you cook.")
            }

            Section {
                Stepper(value: $profile.concurrencyLimit, in: 1...4) {
                    LabeledContent("Tasks at Once") {
                        Text(profile.concurrencyLimit, format: .number)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .accessibilityValue("\(profile.concurrencyLimit) tasks at once")
            } header: {
                Text("Juggling")
            } footer: {
                Text("How many hands-on tasks the schedule gives you at the same time. Passive ones, like a roast in the oven or a dough resting, don't count.")
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
                Text("Recipes show amounts written in the other system converted to yours, rounded to what you can measure. Tap US or Metric on a recipe to convert every amount. Temperatures in steps are shown as written for now.")
            }
        }
        .animation(.default, value: profile.concurrencyLimit)
    }
}

extension Proficiency {
    var title: String {
        switch self {
        case .learning: "Learning"
        case .confident: "Confident"
        case .advanced: "Advanced"
        }
    }

    /// One sentence each (03 §3.17).
    var explanation: String {
        switch self {
        case .learning: "You follow recipes closely. The schedule allows extra time for prep and technique."
        case .confident: "You're at home with most recipes. Times are taken as the recipe gives them."
        case .advanced: "Fast hands and a feel for timing. The schedule tightens the estimates."
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
