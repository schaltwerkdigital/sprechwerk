import SwiftUI

/// "Mikrofon" in the general settings: which input dictation records from. The system
/// default stays the default; a chosen microphone only applies to Sprechwerk and falls back
/// to the system default while it is not connected.
struct MicrophoneSection: View {
    @Bindable var appState: AppState
    @State private var devices: [MicrophoneDevices.Device] = []
    @State private var systemDefault: MicrophoneDevices.Device?

    private var preferredUID: String { appState.appSettings.preferredMicrophoneUID }
    private var preferred: MicrophoneDevices.Device? {
        MicrophoneDevices.resolve(preferredUID: preferredUID, among: devices)
    }
    private var isMissing: Bool { !preferredUID.isEmpty && preferred == nil }
    /// What the next dictation records from.
    private var active: MicrophoneDevices.Device? { preferred ?? systemDefault }

    var body: some View {
        SettingsSection(title: "Mikrofon") {
            HStack(spacing: 8) {
                Text("Diktieren mit")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { preferredUID },
                    set: { choose($0) }
                )) {
                    Text(defaultLabel).tag("")
                    ForEach(devices) { device in
                        Text(device.isVirtual ? "\(device.name) (virtuell)" : device.name).tag(device.uid)
                    }
                    if isMissing {
                        Text("\(appState.appSettings.preferredMicrophoneName) (nicht verbunden)").tag(preferredUID)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
            }

            Text(hint)
                .font(.ui(12))
                .foregroundStyle(active?.isVirtual == true ? AnyShapeStyle(BlitztextTheme.danger) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: refresh)
    }

    private var defaultLabel: String {
        guard let systemDefault else { return "Systemstandard" }
        return "Systemstandard (\(systemDefault.name))"
    }

    private var hint: String {
        var text: String
        if isMissing {
            text = "\u{201E}\(appState.appSettings.preferredMicrophoneName)\u{201C} ist nicht verbunden. Bis dahin nimmt Sprechwerk den Systemstandard."
        } else if preferredUID.isEmpty {
            text = "Sprechwerk nimmt, was macOS als Eingang eingestellt hat. Ein hier gew\u{00E4}hltes Mikrofon gilt nur f\u{00FC}r Sprechwerk."
        } else {
            text = "Gilt nur f\u{00FC}r Sprechwerk. Ist es nicht verbunden, nimmt Sprechwerk den Systemstandard."
        }
        if let active, active.isVirtual {
            text += " \u{201E}\(active.name)\u{201C} ist ein virtuelles Ger\u{00E4}t und liefert nur Ton, solange die zugeh\u{00F6}rige App l\u{00E4}uft (etwa Krisp oder MOTIV Mix). Kommt kein Text an, hier ein echtes Mikrofon w\u{00E4}hlen."
        }
        text += " Meetings nehmen weiter \u{00FC}ber den Systemstandard auf."
        return text
    }

    private func choose(_ uid: String) {
        var settings = appState.appSettings
        settings.preferredMicrophoneUID = uid
        settings.preferredMicrophoneName = devices.first { $0.uid == uid }?.name ?? (uid.isEmpty ? "" : settings.preferredMicrophoneName)
        appState.appSettings = settings
        refresh()
    }

    private func refresh() {
        devices = MicrophoneDevices.inputs()
        systemDefault = MicrophoneDevices.systemDefault
    }
}
