import Foundation

/// The experiment's switches. Off by default: nothing in the app changes until the person turns it on.
package struct LyricsExperimentSettings: Equatable, Sendable {
    package var enabled = false
    package var engine = LyricEngine.speechAnalyzer
    package var separateVocals = true

    package init(enabled: Bool = false, engine: LyricEngine = .speechAnalyzer, separateVocals: Bool = true) {
        self.enabled = enabled
        self.engine = engine
        self.separateVocals = separateVocals
    }
}

package let lyricsEnabledKey = "lyricsExperimentEnabled"
package let lyricsEngineKey = "lyricsExperimentEngine"
package let lyricsSeparateKey = "lyricsExperimentSeparateVocals"

package protocol LyricsExperimentStoring {
    func load() -> LyricsExperimentSettings
    func save(_ settings: LyricsExperimentSettings)
}

/// Backed by the app's defaults, like `PlayModeStore`: a missing or bad value falls back to its default on its own.
package struct LyricsExperimentStore: LyricsExperimentStoring {
    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package func load() -> LyricsExperimentSettings {
        var settings = LyricsExperimentSettings()
        if let stored = defaults.object(forKey: lyricsEnabledKey) as? Bool { settings.enabled = stored }
        if let raw = defaults.object(forKey: lyricsEngineKey) as? String, let engine = LyricEngine(rawValue: raw) { settings.engine = engine }
        if let stored = defaults.object(forKey: lyricsSeparateKey) as? Bool { settings.separateVocals = stored }
        return settings
    }

    package func save(_ settings: LyricsExperimentSettings) {
        defaults.set(settings.enabled, forKey: lyricsEnabledKey)
        defaults.set(settings.engine.rawValue, forKey: lyricsEngineKey)
        defaults.set(settings.separateVocals, forKey: lyricsSeparateKey)
    }
}
