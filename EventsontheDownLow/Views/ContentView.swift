import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = EventListViewModel()
    @State private var editingEvent: CalendarEvent?
    @State private var showingNewEvent = false
    /// Ticked forward once a minute (see the .task below) and passed down
    /// to every EventRowView, so all rows' "Due in..." text updates
    /// together while the app is open — not tied to which rows happen to
    /// be expanded.
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.occurrences) { occurrence in
                    EventRowView(occurrence: occurrence, now: now) {
                        editingEvent = occurrence.event
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            viewModel.delete(occurrence.event)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: HelpDrawerMetrics.handleHeight)
            }
            .overlay(alignment: .top) {
                // GeometryReader lives here, nested inside an .overlay on
                // the List, rather than wrapping the List as NavigationStack's
                // direct child. GeometryReader as a NavigationStack's direct
                // child is a known troublemaker for nav bar layout on iOS —
                // it was silently breaking the title/toolbar entirely here.
                // An .overlay doesn't affect the underlying List's size
                // negotiation with its ancestors, so the List (and therefore
                // NavigationStack's nav bar) lays out normally.
                GeometryReader { geo in
                    HelpDrawer(availableHeight: geo.size.height) {
                        eventsHelpContent
                    }
                }
            }
            .navigationTitle("Events onthe DL")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewEvent) {
                EventEditView(event: nil) { saved in
                    viewModel.addOrUpdate(saved)
                }
            }
            .sheet(item: $editingEvent) { event in
                EventEditView(event: event) { saved in
                    viewModel.addOrUpdate(saved)
                }
            }
        }
        // Single shared clock for the whole list: ticks every 60 seconds
        // for as long as this view is on screen (effectively "while the
        // app is open," since this is the app's root view).
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                now = Date()
            }
        }
    }

    // HELP DOC NOTE: sourced from HELP_DOCUMENTATION_PLAN.md sections 1, 2, 5.
    // Keep this in sync if that plan's wording changes.
    @ViewBuilder
    private var eventsHelpContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HelpItem("Expand", "Long press on event to expand and see images and notes. If there are no notes or images, event cannot expand.")
            
            HelpItem("Theming", "This application will follow the light/dark theme for your phone.")

             HelpItem("Adding an event","Tap + to create a new event.")

                        
            HelpItem("Why does the event date keep changing?", "A repeating event shows only one row here — its next upcoming occurrence — rather than a separate row for every day. You open the event to see the repeating schedule and make any changes.")
                        
            HelpItem("Editing & deleting", "Tap an event to edit it. Swipe left to delete. Deleting a repeating event removes the whole series, not just one occurrence.")

        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
