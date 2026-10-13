import Foundation

package let shuffleSettingKey = "shuffleEnabled"
package let repeatSettingKey = "repeatMode"

package protocol PlayModeStoring {
    func load() -> (shuffle: Bool, repeatMode: RepeatMode)
    func saveShuffle(_ on: Bool)
    func saveRepeat(_ mode: RepeatMode)
}

/// Backed by the app's own defaults. A stored value that is missing or not one of the allowed values falls
/// back to off individually, so a good value is not lost because the other is bad.
package struct PlayModeStore: PlayModeStoring {
    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package func load() -> (shuffle: Bool, repeatMode: RepeatMode) {
        var shuffle = false
        if let stored = defaults.object(forKey: shuffleSettingKey) as? NSNumber,
           CFGetTypeID(stored) == CFBooleanGetTypeID() {
            shuffle = stored.boolValue
        }
        var repeatMode = RepeatMode.off
        if let stored = defaults.object(forKey: repeatSettingKey) as? String, let mode = RepeatMode(rawValue: stored) {
            repeatMode = mode
        }
        return (shuffle, repeatMode)
    }

    package func saveShuffle(_ on: Bool) { defaults.set(on, forKey: shuffleSettingKey) }
    package func saveRepeat(_ mode: RepeatMode) { defaults.set(mode.rawValue, forKey: repeatSettingKey) }
}
