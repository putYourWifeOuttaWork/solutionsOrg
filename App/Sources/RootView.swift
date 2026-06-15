import SwiftUI
import UniformTypeIdentifiers
import PrepOSCore

/// The top-level navigation shell. A sidebar of the main surfaces (PRD §5.2) with the
/// quick-capture bar pinned on top and the whole window acting as a file drop target (C1.1).
struct RootView: View {
    @EnvironmentObject private var engine: PrepOSEngine
    @State private var selection: Section = .needsSorting
    @State private var dropTargeted = false

    /// The primary surfaces of PrepOS, in sidebar order.
    enum Section: String, CaseIterable, Identifiable {
        case today = "Today / This Week"
        case needsSorting = "Needs Sorting"
        case buckets = "Buckets"
        case digests = "Digests"

        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .today: return "calendar.day.timeline.left"
            case .needsSorting: return "tray.full"
            case .buckets: return "square.stack.3d.up"
            case .digests: return "doc.text"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage).tag(section)
            }
            .navigationTitle("PrepOS")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                CaptureBar()
                Divider().padding(.top, 8)
                detail
            }
        }
        .overlay(alignment: .top) { statusBanner }
        .onDrop(of: [.fileURL, .plainText], isTargeted: $dropTargeted) { providers in
            handleDrop(providers); return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 3)
                    .padding(6).allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .needsSorting: NeedsSortingView()
        case .buckets: BucketsView()
        case .today, .digests: ComingSoon(section: selection)
        }
    }

    @ViewBuilder private var statusBanner: some View {
        switch engine.status {
        case .starting:
            Label("Opening encrypted database…", systemImage: "lock.rotation")
                .padding(8).background(.thinMaterial, in: Capsule()).padding(.top, 4)
        case .failed(let message):
            Label("Engine error: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(.top, 4)
        case .ready:
            EmptyView()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { await engine.capture(urls: [url]) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string else { return }
                    Task { await engine.capture(text: string) }
                }
            }
        }
    }
}

/// Placeholder for surfaces that arrive in later phases (calendar, digests).
private struct ComingSoon: View {
    let section: RootView.Section
    var body: some View {
        ContentUnavailableView(section.rawValue, systemImage: section.systemImage,
                               description: Text("Coming in a later phase."))
            .navigationTitle(section.rawValue)
    }
}
