import SwiftUI

/// Which build this is (04 §5.1 "Build identifier", ux-notes row 55): the short commit and the UTC
/// time the project's Build Info phase writes into `BuildInfo.plist` on every build.
struct BuildInfo: Equatable {
    let commit: String
    let date: Date?

    static let current: BuildInfo? = {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let commit = plist["commit"] as? String, !commit.isEmpty else { return nil }
        let date = (plist["date"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
        return BuildInfo(commit: commit, date: date)
    }()

    /// "Build 8dba44e · Oct 20", in the cook's time zone; the year joins it once it isn't this one.
    var text: String {
        guard let date else { return "Build \(commit)" }
        let thisYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let day = thisYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.month(.abbreviated).day().year())
        return "Build \(commit) · \(day)"
    }
}

/// Profile → About: the build, and the sync state with its detail a tap away.
struct AboutSection: View {
    @Environment(SyncMonitor.self) private var sync

    var body: some View {
        Section {
            Text(BuildInfo.current?.text ?? "Build unknown")
                .textSelection(.enabled)
            NavigationLink {
                SyncStatusView()
            } label: {
                SyncSummaryLabel(state: sync.state)
            }
        } header: {
            Text("About")
        }
    }
}

/// The sync state in one line, refreshed so "2 minutes ago" stays true.
private struct SyncSummaryLabel: View {
    let state: SyncMonitor.State

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Sync")
                    Text(state.summary(now: context.date))
                        .font(.subheadline)
                        .foregroundStyle(state.isIssue ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            } icon: {
                Image(systemName: state.systemImage)
                    .foregroundStyle(state.isIssue ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
            }
        }
    }
}

/// The sync state in full: what is happening, what to do, and the error behind it.
struct SyncStatusView: View {
    @Environment(SyncMonitor.self) private var sync

    var body: some View {
        let state = sync.state
        Form {
            Section {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Label {
                        Text(state.summary(now: context.date))
                            .font(.headline)
                    } icon: {
                        Image(systemName: state.systemImage)
                            .foregroundStyle(state.isIssue ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                    }
                }
                Text(state.explanation)
                    .foregroundStyle(.secondary)
            } footer: {
                if let reason = state.reason {
                    Text(reason)
                }
            }
            Section {
                LabeledContent("Store", value: storeText)
                if let lastChange = sync.lastChange {
                    LabeledContent("Last Change", value: lastChange.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var storeText: String {
        switch sync.store {
        case .cloudKit: "iCloud"
        case .local: "This device only"
        case .inMemory: "Memory only"
        }
    }
}

/// The flag at the top of Recipes while a sync issue stands (ux-notes row 56), drawn like the
/// review row; it opens the sync detail.
struct SyncIssueRow: View {
    let state: SyncMonitor.State
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(state.flagTitle)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows why, and what to do.")
    }
}
