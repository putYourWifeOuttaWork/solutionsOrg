import SwiftUI
import UniformTypeIdentifiers

/// The always-present quick-capture affordance (PRD C1.2, C1.7 — one gesture, no tagging).
/// Paste/type text and hit Capture, or drop files anywhere on the window (handled in RootView).
struct CaptureBar: View {
    @EnvironmentObject private var engine: PrepOSEngine
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(.secondary)
                TextField("Paste a transcript or note, or drop a file onto the window…",
                          text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit(capture)
                Button("Capture", action: capture)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if let outcome = engine.lastOutcome {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(outcome).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("embedder: \(engine.embedderName)").font(.caption2).foregroundStyle(.tertiary)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func capture() {
        let toCapture = text
        text = ""
        Task { await engine.capture(text: toCapture) }
    }
}
