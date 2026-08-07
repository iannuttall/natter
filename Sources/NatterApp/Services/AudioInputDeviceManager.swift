import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import Observation

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let audioDeviceID: AudioDeviceID
}

extension Notification.Name {
    static let natterAudioInputSelectionDidChange = Notification.Name(
        "is.ian.natter.audio-input-selection-did-change"
    )
}

@MainActor
@Observable
final class AudioInputDeviceManager {
    static let shared = AudioInputDeviceManager()

    private let defaults: UserDefaults
    private var connectionObservers: [NSObjectProtocol] = []

    private(set) var devices: [AudioInputDevice] = []
    var selectedDeviceUID: String {
        didSet {
            defaults.set(selectedDeviceUID, forKey: Keys.selectedDeviceUID)
            NotificationCenter.default.post(name: .natterAudioInputSelectionDidChange, object: nil)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedDeviceUID = defaults.string(forKey: Keys.selectedDeviceUID) ?? ""
        refresh()

        let center = NotificationCenter.default
        for name in [
            AVCaptureDevice.wasConnectedNotification,
            AVCaptureDevice.wasDisconnectedNotification
        ] {
            connectionObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    var selectedDeviceID: AudioDeviceID? {
        guard !selectedDeviceUID.isEmpty else { return nil }
        return devices.first { $0.id == selectedDeviceUID }?.audioDeviceID
    }

    var selectedDeviceIsUnavailable: Bool {
        !selectedDeviceUID.isEmpty && selectedDeviceID == nil
    }

    func refresh() {
        devices = CoreAudioInputDevices.all().sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private enum Keys {
        static let selectedDeviceUID = "audio.selectedInputDeviceUID"
    }
}

private enum CoreAudioInputDevices {
    static func all() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &byteCount
        ) == noErr else { return [] }

        let count = Int(byteCount) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        let status = deviceIDs.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &byteCount,
                bytes.baseAddress!
            )
        }
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard hasInputStreams(deviceID),
                  let uid = stringProperty(
                      kAudioDevicePropertyDeviceUID,
                      deviceID: deviceID
                  ),
                  let name = stringProperty(
                      kAudioObjectPropertyName,
                      deviceID: deviceID
                  ) else { return nil }
            return AudioInputDevice(id: uid, name: name, audioDeviceID: deviceID)
        }
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        return AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &byteCount
        ) == noErr && byteCount >= MemoryLayout<AudioStreamID>.size
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString? = nil
        var byteCount = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &byteCount,
                pointer
            )
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
