import AppKit
import Combine

/// Accessibility identifiers recorded in `ui-manifest.json`.
enum ElementID {
    static let nowPlaying = "playback.nowplaying"
    static let playPause = "playback.playpause"
    static let stop = "playback.stop"
    static let previous = "playback.previous"
    static let next = "playback.next"
    static let position = "playback.position"
    static let elapsed = "playback.elapsed"
    static let remaining = "playback.remaining"
    static let volume = "playback.volume"
    static let mute = "playback.mute"
    static let shuffle = "playlist.shuffle"
    static let repeatMode = "playlist.repeat"
    static let tracks = "playlist.tracks"
    static let add = "playlist.add"
    static let remove = "playlist.remove"
    static let emptyHint = "playlist.empty"
}

/// The first group of a playlist window: what is playing and the controls for it. Standard controls only.
/// Self-contained, so any host window can embed it.
final class TransportControlsView: NSStackView {
    private let viewModel: TransportViewModel
    private var cancellables = Set<AnyCancellable>()

    let nowPlayingLabel = NSTextField(labelWithString: "")
    let previousButton = NSButton()
    let playPauseButton = NSButton()
    let stopButton = NSButton()
    let nextButton = NSButton()
    let positionSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let elapsedLabel = NSTextField(labelWithString: "0:00")
    let durationLabel = NSTextField(labelWithString: "-0:00")   // time remaining; unlike elapsed it never reads the same text
    let muteButton = NSButton()
    let volumeSlider = NSSlider(value: volumeDefault, minValue: volumeMinimum, maxValue: volumeMaximum, target: nil, action: nil)

    static let nothingPlayingText = "Nothing playing"
    private static let groupSpacing: CGFloat = 10
    private static let rowSpacing: CGFloat = 8
    private static let volumeSliderWidth: CGFloat = 140

    init(viewModel: TransportViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = Self.groupSpacing
        configureControls()
        addArrangedSubview(nowPlayingLabel)
        let buttons = transportRow()
        addArrangedSubview(buttons)
        buttons.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true     // the usual player layout
        let position = positionRow()
        addArrangedSubview(position)
        addArrangedSubview(volumeRow())
        // The position row fills the group's width, so the slider gives way and the track length is never clipped.
        position.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.render() } }
            .store(in: &cancellables)
        render()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Build

    private func configureControls() {
        nowPlayingLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
        nowPlayingLabel.lineBreakMode = .byTruncatingMiddle
        identify(nowPlayingLabel, ElementID.nowPlaying, "Now playing")

        configure(previousButton, symbol: "backward.fill", id: ElementID.previous, label: "Previous", action: #selector(previousPressed))
        configure(playPauseButton, symbol: "play.fill", id: ElementID.playPause, label: "Play", action: #selector(playPausePressed))
        configure(stopButton, symbol: "stop.fill", id: ElementID.stop, label: "Stop", action: #selector(stopPressed))
        configure(nextButton, symbol: "forward.fill", id: ElementID.next, label: "Next", action: #selector(nextPressed))
        configure(muteButton, symbol: "speaker.wave.2.fill", id: ElementID.mute, label: "Mute", action: #selector(mutePressed))
        muteButton.setButtonType(.pushOnPushOff)

        positionSlider.target = self
        positionSlider.action = #selector(positionChanged)
        positionSlider.isContinuous = true
        identify(positionSlider, ElementID.position, "Position")
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged)
        volumeSlider.isContinuous = true
        identify(volumeSlider, ElementID.volume, "Volume")

        for label in [elapsedLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            label.textColor = .secondaryLabelColor
        }
        identify(elapsedLabel, ElementID.elapsed, "Elapsed time")
        identify(durationLabel, ElementID.remaining, "Time remaining")
        volumeSlider.widthAnchor.constraint(equalToConstant: Self.volumeSliderWidth).isActive = true
    }

    private func configure(_ button: NSButton, symbol: String, id: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        identify(button, id, label)
    }

    private func identify(_ view: NSView, _ id: String, _ label: String) {
        view.setAccessibilityIdentifier(id)
        view.setAccessibilityLabel(label)
    }

    private func transportRow() -> NSStackView {
        let row = NSStackView(views: [previousButton, playPauseButton, stopButton, nextButton])
        row.spacing = Self.rowSpacing
        return row
    }

    private func positionRow() -> NSStackView {
        let row = NSStackView(views: [elapsedLabel, positionSlider, durationLabel])
        row.spacing = Self.rowSpacing
        positionSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func volumeRow() -> NSStackView {
        let row = NSStackView(views: [muteButton, volumeSlider])
        row.spacing = Self.rowSpacing
        return row
    }

    // MARK: Render

    /// Always shows the real state, including changes made from outside this view, such as a script.
    func render() {
        let vm = viewModel
        nowPlayingLabel.stringValue = vm.nowPlaying.isEmpty ? Self.nothingPlayingText : vm.nowPlaying
        let playing = vm.isPlaying
        playPauseButton.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: playing ? "Pause" : "Play")
        playPauseButton.setAccessibilityLabel(playing ? "Pause" : "Play")
        playPauseButton.setAccessibilityValue(playing ? "playing" : "paused")
        stopButton.isEnabled = vm.trackControlsAvailable
        positionSlider.isEnabled = vm.trackControlsAvailable
        previousButton.isEnabled = vm.skipControlsAvailable
        nextButton.isEnabled = vm.skipControlsAvailable
        positionSlider.maxValue = max(vm.duration, 1)
        if !positionSlider.isHighlighted { positionSlider.doubleValue = vm.position }
        elapsedLabel.stringValue = TransportViewModel.formatTime(vm.position)
        durationLabel.stringValue = "-" + TransportViewModel.formatTime(max(0, vm.duration - vm.position))
        if !volumeSlider.isHighlighted { volumeSlider.doubleValue = vm.volume }
        muteButton.state = vm.isMuted ? .on : .off
        muteButton.image = NSImage(systemSymbolName: vm.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                   accessibilityDescription: "Mute")
        muteButton.setAccessibilityValue(vm.isMuted ? "on" : "off")
    }

    // MARK: Actions (the same view-model methods scripts call)

    @objc func previousPressed() { try? viewModel.previous() }
    @objc func playPausePressed() { viewModel.playPause() }
    @objc func stopPressed() { try? viewModel.stop() }
    @objc func nextPressed() { try? viewModel.next() }
    @objc func mutePressed() { viewModel.toggleMute() }
    @objc func positionChanged() { try? viewModel.seek(toSeconds: positionSlider.doubleValue) }
    @objc func volumeChanged() { try? viewModel.setVolume(volumeSlider.doubleValue) }
}

/// The second group: Shuffle (on/off) and Repeat (off, all, one). Two separate controls.
final class PlayModeControls: NSStackView {
    private let settings: PlayModeSettings
    private var cancellables = Set<AnyCancellable>()
    let shuffleButton = NSButton()
    let repeatButton = NSButton()

    init(settings: PlayModeSettings) {
        self.settings = settings
        super.init(frame: .zero)
        spacing = 8
        shuffleButton.setButtonType(.pushOnPushOff)
        shuffleButton.bezelStyle = .texturedRounded
        shuffleButton.imagePosition = .imageLeading
        shuffleButton.title = "Shuffle"
        shuffleButton.target = self
        shuffleButton.action = #selector(shufflePressed)
        shuffleButton.setAccessibilityIdentifier(ElementID.shuffle)
        shuffleButton.setAccessibilityLabel("Shuffle")
        repeatButton.setButtonType(.momentaryPushIn)
        repeatButton.bezelStyle = .texturedRounded
        repeatButton.imagePosition = .imageLeading
        repeatButton.target = self
        repeatButton.action = #selector(repeatPressed)
        repeatButton.setAccessibilityIdentifier(ElementID.repeatMode)
        repeatButton.setAccessibilityLabel("Repeat")
        addArrangedSubview(shuffleButton)
        addArrangedSubview(repeatButton)
        settings.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        render()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows the setting that is actually in effect.
    func render() {
        shuffleButton.state = settings.shuffleOn ? .on : .off
        shuffleButton.image = NSImage(systemSymbolName: "shuffle", accessibilityDescription: "Shuffle")
        shuffleButton.setAccessibilityValue(settings.shuffleOn ? "on" : "off")
        shuffleButton.title = settings.shuffleOn ? "Shuffle: On" : "Shuffle: Off"
        let mode = settings.repeatMode
        repeatButton.title = "Repeat: \(mode.rawValue.capitalized)"
        repeatButton.image = NSImage(systemSymbolName: mode == .one ? "repeat.1" : "repeat", accessibilityDescription: "Repeat")
        repeatButton.state = mode == .off ? .off : .on
        repeatButton.setAccessibilityValue(mode.rawValue)
    }

    @objc func shufflePressed() { settings.toggleShuffle(); render() }
    @objc func repeatPressed() { settings.cycleRepeat(); render() }
}
