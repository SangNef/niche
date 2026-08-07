import CoreAudio
import AudioToolbox
import Combine

/// Watches the default output device's master volume via CoreAudio and exposes
/// a transient "just changed" signal so the UI can show a HUD pill for ~1.4s.
final class VolumeObserver: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var isMuted = false
    @Published private(set) var isVisible = false

    private var deviceID: AudioDeviceID = 0
    private var hideWorkItem: DispatchWorkItem?

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    // Wired headphones (headphone jack) commonly don't expose a "main" aggregate
    // volume control at all — only independent per-channel scalar volumes. On
    // those, VirtualMainVolume silently fails to notify, so plugging in wired
    // headphones and pressing the volume keys never shows the HUD. These are the
    // fallback per-channel addresses used when the main one isn't supported.
    private var leftChannelVolumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: 1
    )
    private var rightChannelVolumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: 2
    )
    private var usesPerChannelVolume = false

    // Mute is a separate property from volume level — toggling mute (Mute key,
    // Control Center) doesn't touch VirtualMainVolume, so it needs its own listener.
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    // Fires whenever the system's default output device changes (headphone
    // plug/unplug, Bluetooth device connect/disconnect, AirPlay, etc), so the
    // volume/mute listeners below can be moved onto the new device.
    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // Kept so rebindToDefaultDevice() can remove exactly the blocks it added —
    // AudioObjectRemovePropertyListenerBlock only unregisters on reference match.
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var leftChannelVolumeListener: AudioObjectPropertyListenerBlock?
    private var rightChannelVolumeListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?

    init() {
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, DispatchQueue.main
        ) { [weak self] _, _ in
            self?.rebindToDefaultDevice()
        }
        rebindToDefaultDevice()
    }

    /// (Re)attaches volume/mute listeners to whatever the default output device
    /// currently is. Without this, switching outputs (e.g. connecting AirPods)
    /// leaves the listeners on the old device, so volume key presses on the new
    /// device never trigger the HUD.
    private func rebindToDefaultDevice() {
        if deviceID != 0 {
            if let listener = volumeListener {
                AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, listener)
            }
            if let listener = leftChannelVolumeListener {
                AudioObjectRemovePropertyListenerBlock(deviceID, &leftChannelVolumeAddress, DispatchQueue.main, listener)
            }
            if let listener = rightChannelVolumeListener {
                AudioObjectRemovePropertyListenerBlock(deviceID, &rightChannelVolumeAddress, DispatchQueue.main, listener)
            }
            if let listener = muteListener {
                AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, listener)
            }
        }
        volumeListener = nil
        leftChannelVolumeListener = nil
        rightChannelVolumeListener = nil
        muteListener = nil

        deviceID = Self.defaultOutputDevice()
        guard deviceID != 0 else { return }

        // Wired headphones on the built-in jack (and some other devices) don't
        // implement VirtualMainVolume at all — only per-channel scalar volume.
        // Detect that and fall back so the HUD still triggers.
        usesPerChannelVolume = !AudioObjectHasProperty(deviceID, &volumeAddress)

        if usesPerChannelVolume {
            level = Self.currentChannelVolume(
                deviceID: deviceID, left: leftChannelVolumeAddress, right: rightChannelVolumeAddress
            ) ?? 0

            let leftListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
            let rightListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
            leftChannelVolumeListener = leftListener
            rightChannelVolumeListener = rightListener
            AudioObjectAddPropertyListenerBlock(deviceID, &leftChannelVolumeAddress, DispatchQueue.main, leftListener)
            AudioObjectAddPropertyListenerBlock(deviceID, &rightChannelVolumeAddress, DispatchQueue.main, rightListener)
        } else {
            level = Self.currentVolume(deviceID: deviceID, address: volumeAddress) ?? 0

            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
            volumeListener = listener
            AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, listener)
        }

        isMuted = Self.currentMute(deviceID: deviceID, address: muteAddress) ?? false
        let muteListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.muteChanged() }
        self.muteListener = muteListener
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, muteListener)
    }

    private func volumeChanged() {
        let newLevel: Float?
        if usesPerChannelVolume {
            newLevel = Self.currentChannelVolume(
                deviceID: deviceID, left: leftChannelVolumeAddress, right: rightChannelVolumeAddress
            )
        } else {
            newLevel = Self.currentVolume(deviceID: deviceID, address: volumeAddress)
        }
        guard let newLevel else { return }
        level = newLevel
        show()
    }

    private func muteChanged() {
        guard let muted = Self.currentMute(deviceID: deviceID, address: muteAddress) else { return }
        isMuted = muted
        show()
    }

    private func show() {
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

    /// Averages the left/right channel volumes as a stand-in for a main volume
    /// when the device has no VirtualMainVolume control of its own.
    private static func currentChannelVolume(
        deviceID: AudioDeviceID, left: AudioObjectPropertyAddress, right: AudioObjectPropertyAddress
    ) -> Float? {
        let leftLevel = currentVolume(deviceID: deviceID, address: left)
        let rightLevel = currentVolume(deviceID: deviceID, address: right)
        switch (leftLevel, rightLevel) {
        case let (l?, r?): return (l + r) / 2
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil): return nil
        }
    }

    private static func currentMute(deviceID: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool? {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var mutableAddress = address
        let status = AudioObjectGetPropertyData(deviceID, &mutableAddress, 0, nil, &size, &muted)
        return status == noErr ? (muted != 0) : nil
    }
}
