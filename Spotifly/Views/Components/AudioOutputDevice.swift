//
//  AudioOutputDevice.swift
//  Spotifly
//
//  The Mac's default output device, from Core Audio
//

import CoreAudio

/// The Mac's default output device, as Sound settings names it.
enum AudioOutputDevice {
    /// Its name, such as "MacBook Pro-Lautsprecher", or nil if Core Audio names none.
    static func defaultName() -> String? {
        var deviceId = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceId) == noErr,
              deviceId != kAudioObjectUnknown
        else { return nil }

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        guard AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &name) == noErr,
              let name
        else { return nil }
        return name.takeRetainedValue() as String
    }
}
