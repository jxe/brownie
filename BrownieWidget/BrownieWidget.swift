import AppIntents
import SwiftUI
import WidgetKit

// Brownie's home screen widgets: Quick Play (small, medium) and Today (small). They draw
// the snapshot the app writes (WidgetShared.swift); a tap on a meditation runs
// PlayMeditationIntent, which plays it in the app.

@main
struct BrownieWidgets: WidgetBundle {
    var body: some Widget {
        QuickPlayWidget()
        TodayWidget()
    }
}

/// The widget never plays anything itself: the system runs the audio intent in the app.
enum WidgetPlayHandler {
    static func play(filename: String) async {}
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var isPlaceholder = false
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        completion(SnapshotEntry(date: Date(), snapshot: snapshot ?? .placeholder, isPlaceholder: snapshot == nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot(
            updatedAt: .distantPast, recent: [], playingFilename: nil, streak: 0, streakLastDay: nil,
            secondsToday: 0, checkedInToday: false, palette: nil)
        // Redraw just after midnight, so today's minutes and check-in reset and a lapsed
        // streak goes. The app reloads the timeline whenever something changes.
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 5),
                                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(86400)
        completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: snapshot),
                                      SnapshotEntry(date: midnight, snapshot: snapshot)],
                            policy: .never))
    }
}

// MARK: - Look

/// The app's palette tints (AppPalette in MeditationApp.swift), by its raw value.
private func tint(for palette: String?) -> Color {
    let (light, dark): (UInt32, UInt32) = switch palette {
    case "Eucalyptus & Sage": (0x356456, 0xA3D5BF)
    case "Indigo & Lavender": (0x4B5E8F, 0xB9C8F2)
    default: (0xB77909, 0xF2C773)
    }
    return Color(uiColor: UIColor { traits in
        let rgb = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255,
                       blue: CGFloat(rgb & 255) / 255, alpha: 1)
    })
}

private func minutesText(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes) min" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

// MARK: - Quick Play

struct QuickPlayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.quickPlayKind, provider: SnapshotProvider()) { entry in
            QuickPlayView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Play")
        .description("Start a meditation you played recently.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickPlayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var items: [WidgetSnapshot.Item] {
        Array(entry.snapshot.recent.prefix(family == .systemSmall ? 1 : 4))
    }
    private var accent: Color { tint(for: entry.snapshot.palette) }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "leaf")
                    .font(.title2)
                    .foregroundStyle(accent)
                Text("Play a meditation in Brownie and it shows up here.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        } else if family == .systemSmall, let item = items.first {
            small(item)
        } else {
            medium
        }
    }

    private func isPlaying(_ item: WidgetSnapshot.Item) -> Bool {
        item.filename == entry.snapshot.playingFilename
    }

    private func small(_ item: WidgetSnapshot.Item) -> some View {
        Button(intent: PlayMeditationIntent(filename: item.filename)) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: isPlaying(item) ? "waveform" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(accent)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying(item))
                Spacer(minLength: 4)
                Text(item.title)
                    .font(.headline)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                if index > 0 { Divider().padding(.leading, 30) }
                Button(intent: PlayMeditationIntent(filename: item.filename)) {
                    HStack(spacing: 10) {
                        Image(systemName: isPlaying(item) ? "waveform" : "play.fill")
                            .font(.subheadline)
                            .foregroundStyle(accent)
                            .frame(width: 20)
                        Text(item.title)
                            .font(.subheadline.weight(isPlaying(item) ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
}

// MARK: - Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.todayKind, provider: SnapshotProvider()) { entry in
            TodayView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetShared.feelingsURL)
        }
        .configurationDisplayName("Today")
        .description("Your meditation streak, today's listening, and whether you've checked in.")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayView: View {
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot
        let streak = snapshot.streak(at: entry.date)
        let today = snapshot.isToday(at: entry.date)
        let seconds = today ? snapshot.secondsToday : 0
        let checkedIn = today && snapshot.checkedInToday
        let accent = tint(for: snapshot.palette)

        VStack(alignment: .leading, spacing: 0) {
            Text("\(streak)")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(streak > 0 ? accent : .secondary)
                .contentTransition(.numericText())
            Text("day streak")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Label(seconds >= 60 ? minutesText(seconds) : "Not yet", systemImage: "headphones")
                .font(.footnote)
                .foregroundStyle(seconds >= 60 ? .primary : .secondary)
            Label(checkedIn ? "Checked in" : "Check in", systemImage: checkedIn ? "checkmark.circle.fill" : "heart")
                .font(.footnote)
                .foregroundStyle(checkedIn ? .primary : accent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
}
