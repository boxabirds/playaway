import Foundation
import CoreAudio

/// Output-device presence is read from the system default output device, never guessed from a playback error.
protocol OutputDeviceProviding {
    var hasOutputDevice: Bool { get }
}

struct SystemOutputDevices: OutputDeviceProviding {
    var hasOutputDevice: Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != AudioObjectID(kAudioObjectUnknown)
    }
}
