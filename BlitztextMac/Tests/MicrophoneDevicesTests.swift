import XCTest

final class MicrophoneDevicesTests: XCTestCase {
    private let devices = [
        MicrophoneDevices.Device(id: 41, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro-Mikrofon", isVirtual: false),
        MicrophoneDevices.Device(id: 77, uid: "ShureVirtualAudioDevice_UID", name: "MOTIV Mix Virtual", isVirtual: true),
    ]

    func testEmptyChoiceMeansSystemDefault() {
        XCTAssertNil(MicrophoneDevices.resolve(preferredUID: "", among: devices))
    }

    func testChosenConnectedDeviceIsUsed() {
        XCTAssertEqual(MicrophoneDevices.resolve(preferredUID: "BuiltInMicrophoneDevice", among: devices)?.id, 41)
    }

    func testChosenButDisconnectedFallsBackToSystemDefault() {
        XCTAssertNil(MicrophoneDevices.resolve(preferredUID: "USB-Headset-UID", among: devices))
    }

    func testListingWorksWithoutPermission() {
        // Listing devices needs no microphone access; on a CI runner the list may be empty.
        let inputs = MicrophoneDevices.inputs()
        XCTAssertEqual(Set(inputs.map(\.uid)).count, inputs.count, "UIDs are unique")
        XCTAssertFalse(inputs.contains { $0.name.hasPrefix("Sprechwerk") })
    }
}
