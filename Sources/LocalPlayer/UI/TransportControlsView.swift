import PlayawayCore
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
    static let trackPosition = "playback.track_position"
    static let count = "playlist.count"
    /// The playlist's iCloud sync switch in the title bar, and the one-line reason shown when it is disabled.
    static let sync = "playlist.sync"
    static let syncReason = "playlist.sync_reason"
}

/// The top area of a playlist window: what is playing and the controls for it, sized by how often each is used.
/// Play/Pause is the largest and the only filled accent control; Previous and Next are medium; Shuffle, Repeat,
/// volume and Stop are small and grey. Standard controls only. Self-contained, so any host window can embed it;
/// when given the mode controls it places them in the control row, on the left.
final class TransportControlsView: NSStackView {
    private let viewModel: TransportViewModel
    private var cancellables = Set<AnyCancellable>()

    let nowPlayingLabel = NSTextField(labelWithString: "")
    let trackPositionLabel = NSTextField(labelWithString: "")
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

    private enum Metric {
        static let titleSize: CGFloat = 24
        static let positionSize: CGFloat = 12
        static let timeSize: CGFloat = 11
        static let playSide: CGFloat = 56
        static let playGlyph: CGFloat = 26
        static let skipSide: CGFloat = 40
        static let skipGlyph: CGFloat = 20
        static let stopSide: CGFloat = 24
        static let stopGlyph: CGFloat = 12
        static let muteSide: CGFloat = 28
        static let muteGlyph: CGFloat = 14
        static let volumeWidth: CGFloat = 72
        static let transportGap: CGFloat = 14
        static let zoneGap: CGFloat = 12
        static let titleToSeek: CGFloat = 12
        static let seekToControls: CGFloat = 12
        static let smallGap: CGFloat = 8
        static let titleLineGap: CGFloat = 2
    }

    init(viewModel: TransportViewModel, modes: PlayModeControls? = nil) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 0
        configureControls()
        let title = titleBlock()
        let seek = seekBlock()
        let controls = controlRow(modes: modes)
        for block in [title, seek, controls] { addArrangedSubview(block) }
        setCustomSpacing(Metric.titleToSeek, after: title)
        setCustomSpacing(Metric.seekToControls, after: seek)
        // Every block fills the group's width, so the seek bar gives way last and the times are never clipped.
        for block in [title, seek, controls] { block.widthAnchor.constraint(equalTo: widthAnchor).isActive = true }
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.render() } }
            .store(in: &cancellables)
        render()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    /// The name as a title: the file extension is noise in the largest text on screen.
    static func displayTitle(forFileName name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    // MARK: Build

    private func configureControls() {
        nowPlayingLabel.font = .systemFont(ofSize: Metric.titleSize, weight: .bold)
        nowPlayingLabel.lineBreakMode = .byTruncatingMiddle
        identify(nowPlayingLabel, ElementID.nowPlaying, "Now playing")
        trackPositionLabel.font = .systemFont(ofSize: Metric.positionSize)
        trackPositionLabel.textColor = .secondaryLabelColor
        identify(trackPositionLabel, ElementID.trackPosition, "Place in the playlist")

        configure(previousButton, symbol: "backward.fill", size: Metric.skipSide, glyph: Metric.skipGlyph, tint: .labelColor,
                  id: ElementID.previous, label: "Previous", action: #selector(previousPressed))
        configure(nextButton, symbol: "forward.fill", size: Metric.skipSide, glyph: Metric.skipGlyph, tint: .labelColor,
                  id: ElementID.next, label: "Next", action: #selector(nextPressed))
        configure(stopButton, symbol: "stop.fill", size: Metric.stopSide, glyph: Metric.stopGlyph, tint: .secondaryLabelColor,
                  id: ElementID.stop, label: "Stop", action: #selector(stopPressed))
        configure(muteButton, symbol: "speaker.wave.2.fill", size: Metric.muteSide, glyph: Metric.muteGlyph, tint: .secondaryLabelColor,
                  id: ElementID.mute, label: "Mute", action: #selector(mutePressed))
        muteButton.setButtonType(.pushOnPushOff)
        muteButton.imagePosition = .imageOnly      // setting the type resets it
        configurePlayButton()

        positionSlider.target = self
        positionSlider.action = #selector(positionChanged)
        positionSlider.isContinuous = true
        identify(positionSlider, ElementID.position, "Position")
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged)
        volumeSlider.isContinuous = true
        volumeSlider.controlSize = .small
        volumeSlider.trackFillColor = .secondaryLabelColor
        identify(volumeSlider, ElementID.volume, "Volume")
        volumeSlider.widthAnchor.constraint(equalToConstant: Metric.volumeWidth).isActive = true

        for label in [elapsedLabel, durationLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: Metric.timeSize, weight: .regular)
            label.textColor = .secondaryLabelColor
        }
        identify(elapsedLabel, ElementID.elapsed, "Elapsed time")
        identify(durationLabel, ElementID.remaining, "Time remaining")
    }

    private func symbol(_ name: String, glyph: CGFloat, label: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: glyph, weight: .semibold))
    }

    /// A quiet icon button: no bezel, a grey (or label-coloured) glyph, a fixed square target.
    private func configure(_ button: NSButton, symbol name: String, size: CGFloat, glyph: CGFloat, tint: NSColor,
                           id: String, label: String, action: Selector) {
        button.image = symbol(name, glyph: glyph, label: label)
        button.isBordered = false
        button.contentTintColor = tint
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.toolTip = label
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
        identify(button, id, label)
    }

    /// The one prominent control: a standard button in the system's glass style, tinted with the accent colour.
    private func configurePlayButton() {
        let button = playPauseButton
        button.image = symbol("play.fill", glyph: Metric.playGlyph, label: "Play")
        button.bezelStyle = .glass
        button.tintProminence = .primary
        button.controlSize = .extraLarge
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(playPausePressed)
        button.widthAnchor.constraint(equalToConstant: Metric.playSide).isActive = true
        button.heightAnchor.constraint(equalToConstant: Metric.playSide).isActive = true
        identify(button, ElementID.playPause, "Play")
    }

    private func identify(_ view: NSView, _ id: String, _ label: String) {
        view.setAccessibilityIdentifier(id)
        view.setAccessibilityLabel(label)
    }

    /// The track name with its place in the playlist under it, and Stop at the right edge on the name's line.
    private func titleBlock() -> NSView {
        let lines = NSStackView(views: [nowPlayingLabel, trackPositionLabel])
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = Metric.titleLineGap
        lines.translatesAutoresizingMaskIntoConstraints = false
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        let block = NSView()
        block.addSubview(lines)
        block.addSubview(stopButton)
        nowPlayingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            lines.leadingAnchor.constraint(equalTo: block.leadingAnchor),
            lines.topAnchor.constraint(equalTo: block.topAnchor),
            lines.bottomAnchor.constraint(equalTo: block.bottomAnchor),
            lines.trailingAnchor.constraint(lessThanOrEqualTo: stopButton.leadingAnchor, constant: -Metric.smallGap),
            stopButton.trailingAnchor.constraint(equalTo: block.trailingAnchor),
            stopButton.centerYAnchor.constraint(equalTo: nowPlayingLabel.centerYAnchor),
        ])
        return block
    }

    /// The seek bar across the full width with the two times directly under it.
    private func seekBlock() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let times = NSStackView(views: [elapsedLabel, spacer, durationLabel])
        times.spacing = Metric.smallGap
        let block = NSStackView(views: [positionSlider, times])
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 0
        positionSlider.widthAnchor.constraint(equalTo: block.widthAnchor).isActive = true
        times.widthAnchor.constraint(equalTo: block.widthAnchor).isActive = true
        return block
    }

    /// Modes on the left, Previous/Play/Next exactly centred, volume on the right, all on one line.
    private func controlRow(modes: PlayModeControls?) -> NSView {
        let transport = NSStackView(views: [previousButton, playPauseButton, nextButton])
        transport.spacing = Metric.transportGap
        let volume = NSStackView(views: [muteButton, volumeSlider])
        volume.spacing = Metric.smallGap
        let row = NSView()
        var zones: [NSView] = [transport, volume]
        if let modes { zones.append(modes) }
        for zone in zones {
            zone.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(zone)
            zone.centerYAnchor.constraint(equalTo: row.centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Metric.playSide),
            transport.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            volume.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            volume.leadingAnchor.constraint(greaterThanOrEqualTo: transport.trailingAnchor, constant: Metric.zoneGap),
        ])
        if let modes {
            NSLayoutConstraint.activate([
                modes.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                modes.trailingAnchor.constraint(lessThanOrEqualTo: transport.leadingAnchor, constant: -Metric.zoneGap),
            ])
        }
        return row
    }

    // MARK: Render

    /// Always shows the real state, including changes made from outside this view, such as a script.
    func render() {
        let vm = viewModel
        let playing = vm.isPlaying
        nowPlayingLabel.stringValue = vm.nowPlaying.isEmpty
            ? Self.nothingPlayingText : Self.displayTitle(forFileName: vm.nowPlaying)
        nowPlayingLabel.toolTip = vm.nowPlaying.isEmpty ? nil : vm.nowPlaying
        trackPositionLabel.stringValue = vm.trackPosition
        trackPositionLabel.isHidden = vm.trackPosition.isEmpty
        playPauseButton.image = symbol(playing ? "pause.fill" : "play.fill", glyph: Metric.playGlyph, label: playing ? "Pause" : "Play")
        playPauseButton.setAccessibilityLabel(playing ? "Pause" : "Play")
        playPauseButton.setAccessibilityValue(playing ? "playing" : "paused")
        playPauseButton.toolTip = playing ? "Pause" : "Play"
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
        muteButton.image = symbol(vm.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", glyph: Metric.muteGlyph, label: "Mute")
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

/// Shuffle (on/off) and Repeat (off, all, one) as two small icon toggles. Grey when off, accent when on, and the
/// on state also draws the pressed look, so the state is not carried by colour alone. Repeat one has its own glyph.
final class PlayModeControls: NSStackView {
    private enum Metric {
        static let side: CGFloat = 30
        static let glyph: CGFloat = 16
        static let gap: CGFloat = 4
    }

    private let settings: PlayModeSettings
    private var cancellables = Set<AnyCancellable>()
    let shuffleButton = NSButton()
    let repeatButton = NSButton()

    init(settings: PlayModeSettings) {
        self.settings = settings
        super.init(frame: .zero)
        spacing = Metric.gap
        configure(shuffleButton, id: ElementID.shuffle, label: "Shuffle", action: #selector(shufflePressed))
        configure(repeatButton, id: ElementID.repeatMode, label: "Repeat", action: #selector(repeatPressed))
        addArrangedSubview(shuffleButton)
        addArrangedSubview(repeatButton)
        settings.didChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        render()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    private func configure(_ button: NSButton, id: String, label: String, action: Selector) {
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .accessoryBar      // the system style for buttons with togglable state
        button.title = ""
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: Metric.side).isActive = true
        button.heightAnchor.constraint(equalToConstant: Metric.side).isActive = true
        button.setAccessibilityIdentifier(id)
        button.setAccessibilityLabel(label)
        button.imagePosition = .imageOnly      // last: changing the type or bezel resets it
    }

    private func glyph(_ name: String, label: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: Metric.glyph, weight: .semibold))
    }

    /// Shows the setting that is actually in effect.
    func render() {
        let shuffleOn = settings.shuffleOn
        shuffleButton.state = shuffleOn ? .on : .off
        shuffleButton.isBordered = shuffleOn      // on draws the pressed look, so state is not colour alone
        shuffleButton.bezelColor = shuffleOn ? .controlAccentColor : nil
        shuffleButton.image = glyph("shuffle", label: "Shuffle")
        shuffleButton.contentTintColor = shuffleOn ? .controlAccentColor : .secondaryLabelColor
        shuffleButton.toolTip = shuffleOn ? "Shuffle: On" : "Shuffle: Off"
        shuffleButton.setAccessibilityValue(shuffleOn ? "on" : "off")
        let mode = settings.repeatMode
        repeatButton.image = glyph(mode == .one ? "repeat.1" : "repeat", label: "Repeat")
        repeatButton.state = mode == .off ? .off : .on
        repeatButton.isBordered = mode != .off
        repeatButton.bezelColor = mode == .off ? nil : .controlAccentColor
        repeatButton.contentTintColor = mode == .off ? .secondaryLabelColor : .controlAccentColor
        repeatButton.toolTip = "Repeat: \(mode.rawValue.capitalized)"
        repeatButton.setAccessibilityValue(mode.rawValue)
    }

    @objc func shufflePressed() { settings.toggleShuffle(); render() }
    @objc func repeatPressed() { settings.cycleRepeat(); render() }
}
