import SwiftUI
import PrepOSCore

/// The Buckets surface (PRD C3) — shows each bucket and its filed items, so a capture's
/// destination is visible. Read-only for now; link editing and merges come later.
struct BucketsView: View {
    @EnvironmentObject private var engine: PrepOSEngine

    var body: some View {
        Group {
            if engine.buckets.isEmpty {
                ContentUnavailableView("No buckets yet",
                                       systemImage: "square.stack.3d.up",
                                       description: Text("Capture something — confident matches file automatically; the rest go to Needs Sorting."))
            } else {
                List(engine.buckets) { bucket in
                    Section {
                        if bucket.items.isEmpty {
                            Text("No items").font(.callout).foregroundStyle(.tertiary)
                        } else {
                            ForEach(bucket.items) { item in
                                Label(item.title, systemImage: icon(for: item.type))
                                    .lineLimit(1)
                            }
                        }
                    } header: {
                        HStack {
                            Text(bucket.name)
                            Text(bucket.type.rawValue).font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                            Spacer()
                            Text("\(bucket.items.count)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Buckets")
    }

    private func icon(for type: ItemType) -> String {
        switch type {
        case .transcript: return "text.bubble"
        case .note: return "note.text"
        case .record: return "tablecells"
        case .prepMaterial: return "doc.richtext"
        case .asset: return "doc.badge.plus"
        }
    }
}
