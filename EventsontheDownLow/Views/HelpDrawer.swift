import SwiftUI

/// A pull-down drawer for page-specific help content, anchored just below
/// a navigation title. A small handle (line + chevron) sits at the top;
/// dragging it downward reveals help content up to `maxHeightFraction` of
/// the available height, and dragging back up (or tapping the handle)
/// closes it again — same gesture both directions.
///
/// Usage: overlay this at the top of a page, sized against that page's
/// full available height via GeometryReader. See ContentView.swift for
/// the reference usage on the Events list.
///
/// HELP DOC NOTE: this is the delivery mechanism for the content outlined
/// in HELP_DOCUMENTATION_PLAN.md — each page that adopts this should pass
/// in help content specific to that page, per the plan's per-feature outline.
/// Shared layout constant for HelpDrawer, kept outside the generic struct so
/// it can be referenced without specifying a placeholder Content type
/// (e.g. `HelpDrawerMetrics.handleHeight` instead of `HelpDrawer<AnyView>.handleHeight`).
enum HelpDrawerMetrics {
    /// The handle's fixed height (vertical padding + capsule + chevron).
    /// Hosting views should add this as top padding/inset to their main
    /// content so the closed handle doesn't visually overlap it — see
    /// ContentView.swift for the reference usage.
    static let handleHeight: CGFloat = 44
}

/// A simple bold-title + description row, styled for use inside a
/// HelpDrawer's dark content area. Shared across every page's help content
/// rather than each page re-declaring its own row layout.
struct HelpItem: View {
    let title: String
    let detail: String

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct HelpDrawer<Content: View>: View {
    /// Total height available to size the fully-open drawer against
    /// (typically the hosting page's full GeometryReader height).
    let availableHeight: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var isExpanded = false
    @GestureState private var dragTranslation: CGFloat = 0

    private let maxHeightFraction: CGFloat = 0.75
    private var maxHeight: CGFloat { availableHeight * maxHeightFraction }

    /// Live height while dragging, clamped to [0, maxHeight]. Drag is
    /// constrained to only move the drawer toward the opposite of its
    /// current state (can't drag an already-open drawer further open, etc.)
    /// so the gesture always feels like "pull down to open / push up to close."
    private var currentHeight: CGFloat {
        let base: CGFloat = isExpanded ? maxHeight : 0
        return min(max(base + dragTranslation, 0), maxHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            handle

            if currentHeight > 0 {
                ScrollView {
                    content()
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: currentHeight)
                .background(Color.black.opacity(0.94))
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var handle: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.white.opacity(0.7))
                .frame(width: 44, height: 3)
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($dragTranslation) { value, state, _ in
                    if isExpanded {
                        // Only allow dragging up (negative) to close.
                        state = min(value.translation.height, 0)
                    } else {
                        // Only allow dragging down (positive) to open.
                        state = max(value.translation.height, 0)
                    }
                }
                .onEnded { value in
                    let translation = value.translation.height
                    let threshold = maxHeight * 0.25
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if isExpanded {
                            isExpanded = !(translation < -threshold)
                        } else {
                            isExpanded = translation > threshold
                        }
                    }
                }
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        }
        .accessibilityLabel(isExpanded ? "Hide help" : "Show help")
        .accessibilityHint("Drag or double tap to toggle page help")
    }
}
