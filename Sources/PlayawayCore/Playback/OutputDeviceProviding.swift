import Foundation

/// Output-device presence is read from the system default output device, never guessed from a playback error.
package protocol OutputDeviceProviding {
    var hasOutputDevice: Bool { get }
}

/// iOS always has an output route; routing changes arrive as interruption and route-change events instead.
package struct AlwaysPresentOutput: OutputDeviceProviding {
    package init() {}
    package var hasOutputDevice: Bool { true }
}

package enum DefaultOutputDevices {
    package static func make() -> OutputDeviceProviding {
        #if os(macOS)
        SystemOutputDevices()
        #else
        AlwaysPresentOutput()
        #endif
    }
}
