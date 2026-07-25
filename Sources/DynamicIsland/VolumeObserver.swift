import CoreAudio
import AudioToolbox
import Combine

/// Watches the default output device's master volume via CoreAudio and exposes
/// a transient "just changed" signal so the UI can show a HUD pill for ~1.4s.
final class VolumeObserver: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var isVisible = false

    private var deviceID: AudioDeviceID = 0
    private var hideWorkItem: DispatchWorkItem?

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {
        deviceID = Self.defaultOutputDevice()
        guard deviceID != 0 else { return }
        level = Self.currentVolume(deviceID: deviceID, address: volumeAddress) ?? 0

        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main) { [weak self] _, _ in
            self?.volumeChanged()
        }
    }

    private func volumeChanged() {
        guard let newLevel = Self.currentVolume(deviceID: deviceID, address: volumeAddress) else { return }
        level = newLevel
        isVisible = true

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.isVisible = false }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private static func currentVolume(deviceID: AudioDeviceID, address: AudioObjectPropertyAddress) -> Float? {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var mutableAddress = address
        let status = AudioObjectGetPropertyData(deviceID, &mutableAddress, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }
}
