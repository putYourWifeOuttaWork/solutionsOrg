import SwiftUI
import PrepOSCore

/// The Settings scene. For now it surfaces the bucketing thresholds (PRD §8, C2.8) read
/// from `AppConfig` defaults — read-only placeholders until the settings store lands. It
/// also proves the app links `PrepOSCore` by reading real config + version values.
struct SettingsView: View {
    private let config = AppConfig.default

    var body: some View {
        Form {
            Section("Bucketing thresholds (PRD §8)") {
                LabeledContent("Auto-file (T_high)", value: config.tHigh.formatted())
                LabeledContent("Ambiguity floor (T_low)", value: config.tLow.formatted())
                LabeledContent("Tie margin (T_margin)", value: config.tMargin.formatted())
                LabeledContent("Bulk threshold (N_bulk)", value: config.nBulk.formatted())
                LabeledContent("Link traversal depth", value: config.linkTraversalDepth.formatted())
            }
            Section("Calendar") {
                LabeledContent("Sync horizon (days)", value: config.calendarHorizonDays.formatted())
            }
            Section {
                LabeledContent("PrepOS version", value: PrepOS.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 360)
    }
}

#Preview {
    SettingsView()
}
