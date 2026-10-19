import SwiftUI
import PlayawayCore

/// The floating controller's footprint at the bottom of the screen, so lists can scroll clear of it.
enum PlayerBar {
    static let height: CGFloat = 64
    static let bottomMargin: CGFloat = 4
    static let gapAboveIt: CGFloat = 8
    /// The room to leave for a controller of the given height.
    static func inset(forHeight controller: CGFloat) -> CGFloat { controller + bottomMargin + gapAboveIt }
}

enum Chrome {
    static let artworkSide: CGFloat = 44
    static let playButtonSide: CGFloat = 76
    static let playButtonMaxSide: CGFloat = 112
    static let scrubberStep: Double = 1
    static let cardCorner: CGFloat = 24
    /// The sheet's height for the instant before the card has measured its content.
    static let firstCardHeight: CGFloat = 320
    /// The floating controller never grows wider than this, so on an iPad it is a bar in the middle of the songs, not a slab.
    static let controllerMaxWidth: CGFloat = 640
    /// How long the card takes to grow or shrink when artwork comes or goes or the lyrics panel changes.
    static let cardResizeDuration: TimeInterval = 0.35
    /// A change of the card's height smaller than this (points) is layout noise, not a resize.
    static let cardResizeThreshold: CGFloat = 0.5
    /// How long after a resize the old detent stays available, so the slide can finish.
    static let cardResizeSettle: TimeInterval = 0.1
    /// How far up a drag on the controller must go before it counts as opening the card.
    static let openDragDistance: CGFloat = 24
    /// The lyrics panel below the controls: a one-line note when the experiment is off, a short panel while there is
    /// something to do or wait for, and most of the screen once the lyrics are there.
    static let lyricsNoteHeight: CGFloat = 72
    static let lyricsPanelHeight: CGFloat = 168
    static let lyricsPanelFraction: CGFloat = 0.75
    /// The "Lyrics" disclosure row above the section: the system's minimum tap height.
    static let lyricsHeaderHeight: CGFloat = 44
}

/// The floating controller at the bottom, and the player card, which opens in a standard system sheet: the system draws
/// the dimming, follows the finger and decides when to settle open or closed. Tapping the controller or dragging it up
/// opens the card.
struct PlayerChrome: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let active = model.transport.state != .idle
            ZStack(alignment: .bottom) {
                if active {
                    FloatingController()
                        .frame(maxWidth: Chrome.controllerMaxWidth)
                        .background { SeekShortcuts() }
                        .onTapGesture { model.cardOpen = true }
                        .gesture(DragGesture(minimumDistance: Chrome.openDragDistance).onEnded { value in
                            if value.translation.height < -Chrome.openDragDistance { model.cardOpen = true }
                        })
                        .accessibilityHidden(model.cardOpen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .sheet(isPresented: $model.cardOpen) { PlayerCard(screenHeight: geo.size.height).environmentObject(model) }
            .onChange(of: active) { _, isActive in if !isActive { model.cardOpen = false } }
        }
        .ignoresSafeArea(.keyboard)
    }
}

/// The player card, in the system's own sheet. Its sheet follows the card's height: when the artwork appears or goes, the
/// sheet's top edge slides while the controls stay exactly where they are (both measured on screen by the card tests).
/// The sheet's detents are the height it is leaving and the height it is going to; selecting the new one inside an
/// animation makes the system slide the sheet between them (changing a single detent's height snaps), then the old one is
/// dropped. The content sits at the bottom of the sheet, so a change at the top never moves the controls.
struct PlayerCard: View {
    @EnvironmentObject var model: AppModel
    let screenHeight: CGFloat
    @State private var current = Chrome.firstCardHeight
    @State private var leaving: CGFloat?
    @State private var selection: PresentationDetent = .height(Chrome.firstCardHeight)

    var body: some View {
        ScrollView {
            PlayerColumn(showsHandle: true, screenHeight: screenHeight)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in resize(to: measured) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.bottom)
        .accessibilityIdentifier("player-card")
        .presentationDetents(Set([current, leaving].compactMap { $0 }.map { PresentationDetent.height($0) }), selection: $selection)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Chrome.cardCorner)
    }

    private func resize(to measured: CGFloat) {
        guard abs(measured - current) > Chrome.cardResizeThreshold else { return }
        leaving = current
        current = measured
        withAnimation(.easeInOut(duration: Chrome.cardResizeDuration)) { selection = .height(measured) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Chrome.cardResizeDuration + Chrome.cardResizeSettle))
            leaving = nil
        }
    }
}

/// The model's own alerts (an unsaved playlist, the Files question, a failure), attached once at the root so they
/// show in the stack and in the columns alike.
struct ModelAlerts: ViewModifier {
    @EnvironmentObject var model: AppModel

    func body(content: Content) -> some View {
        content
        .alert("This playlist is no longer available", isPresented: $model.showUnsavedOffer) {
            Button("Save Playlist…") { model.saveUnsavedPlaylist() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Its file was deleted or moved. You can save its songs as a new playlist file.") }
        .alert(FilesPrompt.title, isPresented: $model.showFilesPrompt) {
            ForEach(FilesPrompt.buttons, id: \.label) { button in
                switch button.role {
                case .destructive: Button(button.label, role: .destructive) { model.answerFilesPrompt(button.choice) }
                case .defaultAction: Button(button.label) { model.answerFilesPrompt(button.choice) }.keyboardShortcut(.defaultAction)
                case .plain: Button(button.label, role: .cancel) { model.answerFilesPrompt(button.choice) }
                }
            }
        } message: { Text(FilesPrompt.message) }
        .alert("Let Playaway use this whole folder?", isPresented: Binding(get: { model.nudgeFolderName != nil }, set: { if !$0 { model.nudgeAnswered(accepted: false) } })) {
            Button("Choose Folder") { model.nudgeAnswered(accepted: true) }
            Button("Not Now", role: .cancel) { model.nudgeAnswered(accepted: false) }
        } message: { Text("Playaway can then play every song in “\(model.nudgeFolderName ?? "")” on this device without asking again.") }
        .alert("Playlist", isPresented: Binding(get: { model.failureMessage != nil }, set: { if !$0 { model.dismissFailureMessage() } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.failureMessage ?? "") }
    }
}

struct FloatingController: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            if let data = model.metadata?.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: Chrome.artworkSide, height: Chrome.artworkSide)
                    .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.metadata?.title ?? model.transport.nowPlaying).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let detail = detailLine { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Button { model.transport.playPause() } label: {
                Image(systemName: model.transport.state == .playing ? "pause.fill" : "play.fill")
                    .font(.title2).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(model.transport.state == .playing ? "Pause" : "Play")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: PlayerBar.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))    // keeps the list behind it unreadable
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 8).padding(.bottom, PlayerBar.bottomMargin)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.playerBarHeight = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("floating-controller")
    }

    private var detailLine: String? {
        [model.metadata?.artist, model.metadata?.album].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }
}

/// The player's body, shared by the card on the phone (stacked, with the handle) and the Now Playing column on the
/// iPad (stacked in a narrow column, the words beside the controls in a wide one). It reads the transport live; it
/// keeps nothing of its own.
struct PlayerColumn: View {
    @EnvironmentObject var model: AppModel
    let showsHandle: Bool
    let screenHeight: CGFloat
    @ScaledMetric(relativeTo: .largeTitle) private var playButtonSide = Chrome.playButtonSide

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHandle { handle }
            playlistLink
            artwork
            title
            scrubber
            controls
            LyricsPanel()
                .frame(maxWidth: .infinity)
                .frame(height: lyricsPanelHeight)
        }
        .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 16)
    }

    @ViewBuilder private var artwork: some View {
        if let data = model.metadata?.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity).accessibilityHidden(true)
        }
    }

    /// The note alone when the experiment is off; otherwise the header row, plus the section when it is open.
    private var lyricsPanelHeight: CGFloat {
        switch model.lyrics.status {
        case .off: return Chrome.lyricsNoteHeight
        case .ready: return Chrome.lyricsHeaderHeight + (model.lyrics.settings.panelShown ? screenHeight * Chrome.lyricsPanelFraction : 0)
        case .none, .generating, .failed: return Chrome.lyricsHeaderHeight + (model.lyrics.settings.panelShown ? Chrome.lyricsPanelHeight : 0)
        }
    }

    private var handle: some View {
        Capsule().fill(.secondary.opacity(0.4)).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 6)
    }

    @ViewBuilder private var playlistLink: some View {
        if let name = model.activeSession?.name {
            Button { model.playlistLinkTapped() } label: {
                Text(name).font(.footnote).foregroundStyle(.tint)
            }
            .accessibilityHint("Opens the playlist")
            .accessibilityIdentifier("card-link")
        }
    }

    private var title: some View {
        Text(model.metadata?.title ?? model.transport.nowPlaying).font(.title2.weight(.bold)).lineLimit(2)
    }

    /// The position slider and the two times. They are drawn on a clock straight from the engine, so they are always the
    /// engine's position. While a finger is on the slider the song is paused and every move seeks the engine itself, so the
    /// slider, the times and the sound can never disagree.
    private var scrubber: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: model.transport.state != .playing)) { _ in
            let position = model.transport.displayPosition      // the finger during a drag, the engine otherwise
            let duration = model.transport.duration
            VStack(spacing: 2) {
                Slider(value: Binding(get: { position }, set: { try? model.transport.seek(toSeconds: $0) }),
                       in: 0...max(duration, 1), step: Chrome.scrubberStep) { editing in
                    if editing { model.transport.beginScrub() }
                    else { try? model.transport.endScrub(toSeconds: model.transport.position) }
                }
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(TransportViewModel.formatTime(position)) of \(TransportViewModel.formatTime(duration))")
                HStack {
                    Text(TransportViewModel.formatTime(position))
                    Spacer()
                    Text("-" + TransportViewModel.formatTime(max(duration - position, 0)))
                }
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack { shuffleButton; Spacer(); previousButton; Spacer(); playButton; Spacer(); nextButton; Spacer(); repeatButton }
            VStack(spacing: 12) {
                HStack { Spacer(); previousButton; Spacer(); playButton; Spacer(); nextButton; Spacer() }
                HStack { shuffleButton; Spacer(); repeatButton }
            }
        }
        .font(.title3).buttonStyle(.plain)
    }

    private var shuffleButton: some View {
        Button { model.settings.toggleShuffle() } label: {
            Image(systemName: "shuffle").foregroundStyle(model.settings.shuffleOn ? Color.accentColor : .secondary)
                .frame(minWidth: minimumCloudIconTapSize.width, minHeight: minimumCloudIconTapSize.height).contentShape(Rectangle())
        }
        .accessibilityLabel("Shuffle").accessibilityValue(model.settings.shuffleOn ? "On" : "Off")
    }

    private var previousButton: some View {
        Button { try? model.transport.previous() } label: {
            Image(systemName: "backward.fill").font(.title)
                .frame(minWidth: minimumCloudIconTapSize.width, minHeight: minimumCloudIconTapSize.height).contentShape(Rectangle())
        }
        .accessibilityLabel("Previous")
        .keyboardShortcut(.upArrow, modifiers: [])
    }

    private var playButton: some View {
        Button { model.transport.playPause() } label: {
            Image(systemName: model.transport.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                .resizable().frame(width: min(playButtonSide, Chrome.playButtonMaxSide), height: min(playButtonSide, Chrome.playButtonMaxSide))
        }
        .accessibilityLabel(model.transport.state == .playing ? "Pause" : "Play")
        .keyboardShortcut(.space, modifiers: [])
    }

    private var nextButton: some View {
        Button { try? model.transport.next() } label: {
            Image(systemName: "forward.fill").font(.title)
                .frame(minWidth: minimumCloudIconTapSize.width, minHeight: minimumCloudIconTapSize.height).contentShape(Rectangle())
        }
        .accessibilityLabel("Next")
        .keyboardShortcut(.downArrow, modifiers: [])
    }

    private var repeatButton: some View {
        Button { model.settings.cycleRepeat() } label: {
            Image(systemName: model.settings.repeatMode == .one ? "repeat.1" : "repeat")
                .foregroundStyle(model.settings.repeatMode == .off ? Color.secondary : Color.accentColor)
                .frame(minWidth: minimumCloudIconTapSize.width, minHeight: minimumCloudIconTapSize.height).contentShape(Rectangle())
        }
        .accessibilityLabel("Repeat").accessibilityValue(repeatSpoken)
    }

    private var repeatSpoken: String {
        switch model.settings.repeatMode { case .off: "Off"; case .all: "All"; case .one: "One" }
    }
}

/// The keyboard on an iPad (story 38): what each key does, listed in the system's shortcut overlay by the buttons
/// that carry them.
enum Keys {
    static let seekStep: Double = 5
}


extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Left and Right arrows seek by `Keys.seekStep` (an iPad's keyboard); the buttons are not drawn, the shortcuts are what
/// they are for.
struct SeekShortcuts: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            Button("Back 5 seconds") { try? model.transport.seek(toSeconds: max(model.transport.position - Keys.seekStep, 0)) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Forward 5 seconds") { try? model.transport.seek(toSeconds: min(model.transport.position + Keys.seekStep, model.transport.duration)) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
    }
}
