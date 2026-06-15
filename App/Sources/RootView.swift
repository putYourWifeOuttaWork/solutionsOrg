import SwiftUI
import PrepOSCore

/// The top-level navigation shell. A sidebar of the main surfaces (PRD §5.2) with empty
/// placeholder detail views — each becomes a real feature in later phases. The point of
/// the scaffold is that the app launches and every surface is reachable.
struct RootView: View {
    /// The primary surfaces of PrepOS, in sidebar order.
    enum Section: String, CaseIterable, Identifiable {
        case today = "Today / This Week"
        case triage = "Needs Sorting"
        case buckets = "Buckets"
        case digests = "Digests"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .today: return "calendar.day.timeline.left"
            case .triage: return "tray.full"
            case .buckets: return "square.stack.3d.up"
            case .digests: return "doc.text"
            }
        }

        /// One-line description of what the surface will do (PRD reference).
        var blurb: String {
            switch self {
            case .today: return "Upcoming calls, prep status, and one-click entry into each call's workspace (PRD C6.3)."
            case .triage: return "Low-confidence captures awaiting a one-tap home bucket (PRD C2.4)."
            case .buckets: return "Accounts, opportunities, projects, and topics — and the links between them (PRD C3)."
            case .digests: return "Daily and weekly digests of the week ahead (PRD C6.1–C6.2)."
            }
        }
    }

    @State private var selection: Section? = .today

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("PrepOS")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            if let selection {
                PlaceholderSurface(section: selection)
            } else {
                ContentUnavailableView("Select a surface", systemImage: "sidebar.left")
            }
        }
    }
}

/// A "coming soon" placeholder for a not-yet-built surface, naming the PRD requirement it
/// will satisfy so the scaffold documents intent.
struct PlaceholderSurface: View {
    let section: RootView.Section

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: section.systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(section.rawValue)
                .font(.title2.weight(.semibold))
            Text(section.blurb)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("Coming soon")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(section.rawValue)
    }
}

#Preview {
    RootView()
}
