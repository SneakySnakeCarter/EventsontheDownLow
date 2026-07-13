import SwiftUI
import PhotosUI
import UIKit

/// How a recurring event's repetition ends. "Never" is the key addition here —
/// it makes indefinite recurrence (e.g. a daily medicine reminder with no end
/// date) an explicit, discoverable choice instead of an implicit side effect
/// of leaving other fields blank.
///
/// HELP DOC NOTE: this is flagged as the least-obvious feature in the app
/// in HELP_DOCUMENTATION_PLAN.md (section 2) — worth a dedicated callout
/// with a concrete example (e.g. daily medicine reminder) once help content
/// gets written.
private enum RecurrenceEndOption: Hashable {
    case never
    case afterCount
    case onDate
}

/// Unit for a single reminder's "before start" offset, used only for
/// editing UI — everything is converted to/from plain minutes-before for
/// storage (CalendarEvent.reminderOffsets / RecurrenceRule-style encoding).
private enum ReminderUnit: String, CaseIterable, Identifiable {
    case minutes, hours, days
    var id: String { rawValue }
    /// Always-plural label, for the unit picker's menu items (e.g. "Minutes").
    var pluralLabel: String { rawValue.capitalized }
    var minutesPerUnit: Int {
        switch self {
        case .minutes: return 1
        case .hours: return 60
        case .days: return 1440
        }
    }
    /// Singular/plural label matching a specific value, for the row's
    /// display text (e.g. "1 Hour before" vs "2 Hours before").
    func label(for value: Int) -> String {
        let singular: String
        switch self {
        case .minutes: singular = "Minute"
        case .hours: singular = "Hour"
        case .days: singular = "Day"
        }
        return value == 1 ? singular : singular + "s"
    }
}

/// One configured reminder, as edited in the UI. A value of 0 always means
/// "at the event's start time," regardless of unit — a user can add as many
/// of these as they want, each at any interval.
private struct ReminderOption: Identifiable, Equatable {
    let id = UUID()
    var value: Int
    var unit: ReminderUnit

    var totalMinutesBefore: Int { value == 0 ? 0 : value * unit.minutesPerUnit }

    var displayLabel: String {
        guard value > 0 else { return "At time of event" }
        return "\(value) \(unit.label(for: value)) before"
    }

    /// Converts a stored minutes-before value back into a friendly
    /// value+unit pair, picking the largest whole unit that divides evenly
    /// (e.g. 1440 -> 1 day, 90 -> 90 minutes since it isn't a whole hour).
    static func from(minutesBefore: Int) -> ReminderOption {
        guard minutesBefore > 0 else { return ReminderOption(value: 0, unit: .minutes) }
        if minutesBefore.isMultiple(of: 1440) {
            return ReminderOption(value: minutesBefore / 1440, unit: .days)
        }
        if minutesBefore.isMultiple(of: 60) {
            return ReminderOption(value: minutesBefore / 60, unit: .hours)
        }
        return ReminderOption(value: minutesBefore, unit: .minutes)
    }
}

struct EventEditView: View {
    @Environment(\.dismiss) private var dismiss

    let originalEvent: CalendarEvent?
    let onSave: (CalendarEvent) -> Void

    @State private var title: String
    @State private var notes: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var keepEndSyncedWithStart: Bool = true
    @State private var frequency: RecurrenceFrequency
    @State private var interval: Int
    @State private var selectedWeekdays: Set<Int>
    @State private var endOption: RecurrenceEndOption
    @State private var endAfterCount: Int
    @State private var endByDate: Date
    @State private var reminders: [ReminderOption]
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var imageFileName: String?
    @State private var showingCamera = false
    @State private var photoSaveMessage: String?
    @State private var photoSaveMessageIsError = false

    private let weekdaySymbols = Calendar.autoupdatingCurrent.shortWeekdaySymbols // index 0 = Sunday, follows device Region setting

    init(event: CalendarEvent?, onSave: @escaping (CalendarEvent) -> Void) {
        self.originalEvent = event
        self.onSave = onSave
        let now = Date()
        _title = State(initialValue: event?.title ?? "")
        _notes = State(initialValue: event?.notes ?? "")
        _startDate = State(initialValue: event?.startDate ?? now)
        _endDate = State(initialValue: event?.endDate ?? now)
        _frequency = State(initialValue: event?.recurrence.frequency ?? .none)
        _interval = State(initialValue: event?.recurrence.interval ?? 1)
        _selectedWeekdays = State(initialValue: Set(event?.recurrence.byWeekday ?? []))
        if event?.recurrence.count != nil {
            _endOption = State(initialValue: .afterCount)
        } else if event?.recurrence.until != nil {
            _endOption = State(initialValue: .onDate)
        } else {
            _endOption = State(initialValue: .never)
        }
        _endAfterCount = State(initialValue: event?.recurrence.count ?? 10)
        _endByDate = State(initialValue: event?.recurrence.until ?? now.addingTimeInterval(60 * 60 * 24 * 30))
        _reminders = State(initialValue: (event?.reminderOffsets ?? [0]).map(ReminderOption.from(minutesBefore:)))
        _imageFileName = State(initialValue: event?.imageFileName)
        if let fileName = event?.imageFileName {
            if let data = EventImageStore.loadData(for: fileName) {
                _previewImage = State(initialValue: UIImage(data: data))
                #if DEBUG
                print("EventEditView: loaded preview image for '\(fileName)', \(data.count) bytes")
                #endif
            } else {
                #if DEBUG
                print("EventEditView: event has imageFileName '\(fileName)' but EventImageStore couldn't load it")
                #endif
            }
        } else {
            #if DEBUG
            print("EventEditView: event has no imageFileName set")
            #endif
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                // HELP DOC NOTE: HELP_DOCUMENTATION_PLAN.md (section 3) calls
                // out that "photos stay local unless you tap Save to Photos"
                // needs to be stated plainly in user-facing help — this has
                // been a recurring point of confusion during our own testing.
                Section("Photo") {
                    if let previewImage {
                        HStack {
                            Spacer()
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .listRowSeparator(.hidden)
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(previewImage == nil ? "Choose Photo" : "Change Photo", systemImage: "photo.on.rectangle")
                    }

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label(previewImage == nil ? "Take Photo" : "Retake Photo", systemImage: "camera")
                        }
                    }

                    if previewImage != nil {
                        Button {
                            saveCurrentPhotoToLibrary()
                        } label: {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }

                        Button(role: .destructive) {
                            previewImage = nil
                            imageFileName = nil
                            selectedPhotoItem = nil
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                    }

                    Text("Attached photos appear as a thumbnail in reminder notifications, and full-size when expanded. They're only saved within this app unless you tap \"Save to Photos.\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let photoSaveMessage {
                        Text(photoSaveMessage)
                            .font(.caption)
                            .foregroundStyle(photoSaveMessageIsError ? .red : .green)
                    }
                }

                Section("Time") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: startDate) { newValue in
                            if keepEndSyncedWithStart {
                                endDate = newValue
                            }
                        }
                    Toggle("Keep end time synced with start", isOn: $keepEndSyncedWithStart)
                        .onChange(of: keepEndSyncedWithStart) { newValue in
                            if newValue {
                                endDate = startDate
                            }
                        }
                    DatePicker("Ends", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                        .disabled(keepEndSyncedWithStart)
                        .foregroundStyle(keepEndSyncedWithStart ? .secondary : .primary)
                }

                Section("Reminders") {
                    ForEach($reminders) { $reminder in
                        HStack {
                            Stepper(value: $reminder.value, in: 0...999) {
                                Text(reminder.displayLabel)
                            }
                            if reminder.value > 0 {
                                Picker("", selection: $reminder.unit) {
                                    ForEach(ReminderUnit.allCases) { unit in
                                        Text(unit.pluralLabel).tag(unit)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                    }
                    .onDelete { indices in
                        reminders.remove(atOffsets: indices)
                    }

                    Button {
                        reminders.append(ReminderOption(value: 15, unit: .minutes))
                    } label: {
                        Label("Add Reminder", systemImage: "plus.circle")
                    }

                    if reminders.isEmpty {
                        Text("No reminders — this event won't send any notifications.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Add as many reminders as you want, at any interval before the event.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Repeat") {
                    Picker("Frequency", selection: $frequency) {
                        Text("Never").tag(RecurrenceFrequency.none)
                        Text("Daily").tag(RecurrenceFrequency.daily)
                        Text("Weekly").tag(RecurrenceFrequency.weekly)
                        Text("Monthly").tag(RecurrenceFrequency.monthly)
                        Text("Yearly").tag(RecurrenceFrequency.yearly)
                    }

                    if frequency != .none {
                        Stepper("Every \(interval) \(intervalUnitLabel)", value: $interval, in: 1...30)

                        if frequency == .weekly {
                            weekdaySelector
                        }

                        Picker("Ends", selection: $endOption) {
                            Text("Never").tag(RecurrenceEndOption.never)
                            Text("After N Times").tag(RecurrenceEndOption.afterCount)
                            Text("On Date").tag(RecurrenceEndOption.onDate)
                        }
                        if endOption == .never {
                            Text("Repeats indefinitely — good for ongoing reminders like daily medication.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if endOption == .afterCount {
                            Stepper("After \(endAfterCount) occurrences", value: $endAfterCount, in: 1...365)
                        }
                        if endOption == .onDate {
                            DatePicker("On date", selection: $endByDate, displayedComponents: .date)
                        }
                    }
                }

                if originalEvent != nil {
                    Section {
                        Button("Delete Event", role: .destructive) {
                            // handled by row swipe-to-delete in ContentView;
                            // kept here for completeness if wired to a delete callback.
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: HelpDrawerMetrics.handleHeight)
            }
            .overlay(alignment: .top) {
                // GeometryReader lives here, nested inside an .overlay on
                // the Form, rather than wrapping the Form as NavigationStack's
                // direct child — GeometryReader as a NavigationStack's direct
                // child broke the nav bar's title/toolbar entirely (a known
                // iOS layout quirk). An .overlay doesn't affect the Form's
                // own size negotiation with its ancestors, so the nav bar
                // lays out normally.
                GeometryReader { geo in
                    HelpDrawer(availableHeight: geo.size.height) {
                        eventEditHelpContent
                    }
                }
            }
            .navigationTitle(originalEvent == nil ? "New Event" : "Edit Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        // Note: intentionally does NOT delete the previous file here —
                        // if the user cancels this screen instead of saving, the
                        // original event's photo (still referenced by the DB row)
                        // must stay intact. Cleanup of replaced/orphaned files happens
                        // in EventRepository.save() once a change is actually committed.
                        imageFileName = EventImageStore.save(imageData: data)
                        previewImage = uiImage
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCaptureView(
                    onCapture: { image in
                        showingCamera = false
                        if let data = image.jpegData(compressionQuality: 0.9) {
                            imageFileName = EventImageStore.save(imageData: data)
                            previewImage = image
                        }
                    },
                    onCancel: {
                        showingCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
        }
        // Native, built-in behavior for Form/List — dismisses the keyboard
        // as soon as the user starts scrolling/dragging elsewhere, with no
        // custom gesture recognizer that could compete with row buttons
        // (unlike a manual tap gesture, which intercepted the Photo section
        // buttons' taps before they could register).
        .scrollDismissesKeyboard(.immediately)
    }

    // HELP DOC NOTE: sourced from HELP_DOCUMENTATION_PLAN.md sections 2, 3, 4.
    // Keep this in sync if that plan's wording changes.
    @ViewBuilder
    private var eventEditHelpContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HelpItem("Keep end time synced with start", "This makes the event into a reminder.  You can set an actual duration by unchecking this option. If you check the box again, any change you made will disappear and the time will be linked to the start.")

            HelpItem("Repeating an event", "Pick a Frequency, then choose how it ends: Never (repeats indefinitely — good for a daily medicine reminder), After N Times, or On a specific date.")
                        
            HelpItem("Photos", "Choose an existing photo or take a new one with the camera. Photos stay local to this app. If you want to add the photo you your Photos library, then tap \"Save to Photos\" - this cannot be undone.")

            HelpItem("Reminders", "Add as many reminders as you want, each at any interval before the event — or right at the event's start time. Remove any you don't need by swiping left on it.")
        }
    }

    private func saveCurrentPhotoToLibrary() {
        guard let previewImage else { return }
        PhotoLibrarySaver.save(previewImage) { result in
            switch result {
            case .success:
                photoSaveMessage = "Saved to Photos."
                photoSaveMessageIsError = false
            case .denied:
                photoSaveMessage = "Photos access denied. Enable it in Settings to save photos there."
                photoSaveMessageIsError = true
            case .failed(let error):
                photoSaveMessage = "Couldn't save to Photos: \(error.localizedDescription)"
                photoSaveMessageIsError = true
            }
        }
    }

    private var weekdaySelector: some View {
        HStack {
            ForEach(1...7, id: \.self) { weekday in
                let label = weekdaySymbols[weekday - 1]
                Button {
                    if selectedWeekdays.contains(weekday) {
                        selectedWeekdays.remove(weekday)
                    } else {
                        selectedWeekdays.insert(weekday)
                    }
                } label: {
                    Text(label.prefix(1))
                        .frame(width: 28, height: 28)
                        .background(selectedWeekdays.contains(weekday) ? Color.accentColor : Color.gray.opacity(0.2))
                        .foregroundStyle(selectedWeekdays.contains(weekday) ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var intervalUnitLabel: String {
        switch frequency {
        case .none: return ""
        case .daily: return interval == 1 ? "day" : "days"
        case .weekly: return interval == 1 ? "week" : "weeks"
        case .monthly: return interval == 1 ? "month" : "months"
        case .yearly: return interval == 1 ? "year" : "years"
        }
    }

    private func save() {
        var rule = RecurrenceRule()
        rule.frequency = frequency
        rule.interval = max(1, interval)
        rule.byWeekday = frequency == .weekly ? Array(selectedWeekdays).sorted() : []
        switch endOption {
        case .never:
            rule.count = nil
            rule.until = nil
        case .afterCount:
            rule.count = endAfterCount
            rule.until = nil
        case .onDate:
            rule.count = nil
            rule.until = endByDate
        }

        let event = CalendarEvent(
            id: originalEvent?.id,
            title: title,
            notes: notes.isEmpty ? nil : notes,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            recurrence: rule,
            imageFileName: imageFileName,
            reminderOffsets: reminders.map { $0.totalMinutesBefore }.sorted()
        )
        onSave(event)
        dismiss()
    }
}
