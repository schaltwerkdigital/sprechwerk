import CoreAudio
import Foundation

/// The Mac's audio inputs and the one Sprechwerk records from. A microphone chosen in the
/// settings wins; while it is not connected, recording falls back to the system default.
/// Virtual inputs (Krisp, MOTIV Mix, Teams) only deliver sound while their app runs, so a
/// virtual system default is the usual reason for "no text recognized".
enum MicrophoneDevices {
    struct Device: Identifiable, Equatable {
        let id: AudioObjectID
        /// Stays the same across restarts and reconnects, unlike `id`.
        let uid: String
        let name: String
        let isVirtual: Bool
    }

    /// The UID chosen in the settings, empty for the system default. Set by AppState, read
    /// by AudioRecorder when a recording starts.
    nonisolated(unsafe) static var preferredUID = ""

    /// Every device with at least one input channel, by name. Sprechwerk's own aggregate
    /// device for meetings is left out.
    static func inputs() -> [Device] {
        allDeviceIDs()
            .filter(hasInput)
            .compactMap(device)
            .filter { !$0.name.hasPrefix("Sprechwerk") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static var systemDefault: Device? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return device(id)
    }

    /// The chosen microphone when it is connected; nil means: record from the system default.
    static func preferredDevice() -> Device? {
        resolve(preferredUID: preferredUID, among: inputs())
    }

    /// What a recording uses right now.
    static func activeInput() -> Device? {
        preferredDevice() ?? systemDefault
    }

    static func resolve(preferredUID: String, among devices: [Device]) -> Device? {
        guard !preferredUID.isEmpty else { return nil }
        return devices.first { $0.uid == preferredUID }
    }

    // MARK: - Core Audio

    private static func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasInput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func device(_ id: AudioObjectID) -> Device? {
        guard let uid = string(id, kAudioDevicePropertyDeviceUID),
              let name = string(id, kAudioObjectPropertyName)
        else { return nil }
        return Device(id: id, uid: uid, name: name, isVirtual: transportType(id) == kAudioDeviceTransportTypeVirtual)
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value
        else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func transportType(_ id: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &type) == noErr ? type : 0
    }
}
