import SwiftUI

struct EventRowView: View {
    let occurrence: EventOccurrence
    /// Current time, injected from the hosting list rather than tracked
    /// locally — see ContentView.swift, which ticks this once a minute for
    /// every row at once while the app is open, regardless of which rows
    /// happen to be expanded.
    var now: Date = Date()
    var onTapToEdit: (() -> Void)? = nil

    @State private var isExpanded = false
    @State private var thumbnail: UIImage?

    private var hasNotes: Bool {
        guard let notes = occurrence.event.notes else { return false }
        return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasPhoto: Bool {
        occurrence.event.imageFileName != nil
    }

    private var isExpandable: Bool {
        hasNotes || hasPhoto
    }

    private var isExpired: Bool {
        occurrence.occurrenceEnd < Date()
    }

    private var displayDateString: String {
        let base: String
        if occurrence.occurrenceStart == occurrence.occurrenceEnd {
            base = Self.singleFormatter.string(from: occurrence.occurrenceStart)
        } else {
            base = Self.rangeFormatter.string(from: occurrence.occurrenceStart, to: occurrence.occurrenceEnd)
        }
        return occurrence.event.recurrence.isRecurring ? "Next: \(base)" : base
    }

    /// Time remaining until the occurrence's start ("due") time — days if
    /// more than 24 hours away, otherwise hours/minutes. Driven by the
    /// injected `now` rather than reading the clock directly, so every row
    /// updates together whenever the hosting list ticks it forward — see
    /// ContentView.swift.
    private var timeUntilDueString: String {
        let interval = occurrence.occurrenceStart.timeIntervalSince(now)

        if interval <= 0 {
            return "Overdue"
        }

        let secondsPerDay: TimeInterval = 24 * 60 * 60
        if interval >= secondsPerDay {
            let days = Int(interval / secondsPerDay)
            return days == 1 ? "Due in 1 day" : "Due in \(days) days"
        }

        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 && minutes > 0 {
            return "Due in \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "Due in \(hours)h"
        } else {
            return "Due in \(minutes)m"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack {
                    thumbnailView

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(occurrence.event.title)
                                .font(.headline)
                                .foregroundStyle(isExpired ? Color(.systemGray3) : .primary)
                            if occurrence.event.recurrence.isRecurring {
                                Image(systemName: "repeat")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(displayDateString)
                            .font(.subheadline)
                            .foregroundStyle(isExpired ? Color(.systemGray3) : .secondary)
                        Text(timeUntilDueString)
                            .font(.caption)
                            .foregroundStyle(isExpired ? Color(.systemGray3) : Color(.tertiaryLabel))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                // Long-press the row itself to expand and show notes/photo.
                // Only does anything if there's actually something to show —
                // a plain onLongPressGesture rather than a Button, since this
                // area no longer opens the editor (that moved to the button
                // on the right).
                .onLongPressGesture {
                    guard isExpandable else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                // A regular tap closes it back up again once expanded.
                // Does nothing while already collapsed — tapping a collapsed
                // row has no action (editing lives on the pencil button).
                .onTapGesture {
                    guard isExpanded else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }

                // Tap this to edit the event — expand/collapse moved to the
                // long-press gesture on the row above.
                Button {
                    onTapToEdit?()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isExpanded && isExpandable {
                VStack(alignment: .leading, spacing: 8) {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if hasNotes {
                        Text(occurrence.event.notes ?? "")
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
        .task(id: occurrence.event.imageFileName) {
            guard let fileName = occurrence.event.imageFileName else {
                thumbnail = nil
                return
            }
            if let data = EventImageStore.loadData(for: fileName) {
                thumbnail = UIImage(data: data)
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(isExpired ? 0.5 : 1.0)
        }
    }

    private static let rangeFormatter: DateIntervalFormatter = {
        let f = DateIntervalFormatter()
        // Explicit rather than relying on defaults, so this always follows
        // whatever the device is currently set to (Settings > General >
        // Language & Region), including live changes without needing to
        // relaunch the app.
        f.locale = .autoupdatingCurrent
        f.calendar = .autoupdatingCurrent
        f.timeZone = .autoupdatingCurrent
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private static let singleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.calendar = .autoupdatingCurrent
        f.timeZone = .autoupdatingCurrent
        // Using a template with "j" (rather than a fixed .dateStyle/.timeStyle
        // pair) lets the system choose the correct 12-hour vs 24-hour clock
        // based on the user's actual device setting — Settings > General >
        // Date & Time > 24-Hour Time — not just what their region/locale
        // would default to on its own (someone in a normally-12-hour locale
        // who's manually turned on 24-hour time gets that respected here).
        f.setLocalizedDateFormatFromTemplate("Mdyjmm")
        return f
    }()
}
