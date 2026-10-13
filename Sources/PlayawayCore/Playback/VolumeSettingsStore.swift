import Foundation

package protocol VolumeSettingsStoring {
    func load() -> (volume: Double, isMuted: Bool)
    func saveVolume(_ volume: Double)
    func saveMuted(_ muted: Bool)
}

/// Volume and mute are the player's own settings, stored under two separate keys in the app's own
/// defaults so a damaged value in one never discards a valid value in the other.
package struct VolumeSettingsStore: VolumeSettingsStoring {
    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package func load() -> (volume: Double, isMuted: Bool) {
        var volume = volumeDefault
        if let stored = defaults.object(forKey: volumeSettingKey) as? NSNumber,
           CFGetTypeID(stored) != CFBooleanGetTypeID() {
            let value = stored.doubleValue
            if value.isFinite, value >= volumeMinimum, value <= volumeMaximum {
                volume = value
            }
        }
        var muted = muteDefault
        if let stored = defaults.object(forKey: muteSettingKey) as? NSNumber,
           CFGetTypeID(stored) == CFBooleanGetTypeID() {
            muted = stored.boolValue
        }
        return (volume, muted)
    }

    package func saveVolume(_ volume: Double) {
        defaults.set(volume, forKey: volumeSettingKey)
    }

    package func saveMuted(_ muted: Bool) {
        defaults.set(muted, forKey: muteSettingKey)
    }
}
