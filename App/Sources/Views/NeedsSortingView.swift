import SwiftUI
import PrepOSCore

/// The Needs-Sorting triage inbox (PRD C2.4, T1.6). Each pending item shows its ranked candidate
/// buckets (with scores) plus a way to file it into an existing bucket or a brand-new one.
struct NeedsSortingView: View {
    @EnvironmentObject private var engine: PrepOSEngine

    var body: some View {
        Group {
            if engine.needsSorting.isEmpty {
                ContentUnavailableView("Nothing to sort",
                                       systemImage: "tray",
                                       description: Text("Captured items that can't be auto-filed land here."))
            } else {
                List(engine.needsSorting) { entry in
                    TriageRow(entry: entry)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Needs Sorting")
    }
}

private struct TriageRow: View {
    @EnvironmentObject private var engine: PrepOSEngine
    let entry: TriageEntry

    @State private var newBucketName = ""
    @State private var newBucketType: BucketType = .account

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(reasonLabel).font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
            }

            if entry.candidates.isEmpty {
                Text("No similar bucket — file it into a new one below.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Suggested buckets").font(.caption).foregroundStyle(.secondary)
                ForEach(entry.candidates, id: \.0) { candidate in
                    Button {
                        Task { await engine.resolve(entry, toBucket: candidate.0) }
                    } label: {
                        HStack {
                            Image(systemName: "square.stack.3d.up")
                            Text(candidate.1)
                            Spacer()
                            Text(String(format: "%.0f%%", candidate.2 * 100))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Picker("", selection: $newBucketType) {
                    ForEach(BucketType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .labelsHidden().frame(width: 130)
                TextField("New bucket name", text: $newBucketName)
                    .textFieldStyle(.roundedBorder)
                Button("Create & File") {
                    Task { await engine.resolve(entry, intoNewBucket: newBucketName, type: newBucketType) }
                }
                .disabled(newBucketName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var reasonLabel: String {
        switch entry.reason {
        case .lowConfidence: return "Low confidence"
        case .ambiguousTwoClose: return "Ambiguous — two close"
        case .noMatch: return "No match"
        case .bulkDeferred: return "Bulk import"
        }
    }
}
