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

private enum Chrome {
    static let artworkSide: CGFloat = 44
    static let playButtonSide: CGFloat = 76
    static let playButtonMaxSide: CGFloat = 112
    static let scrubberStep: Double = 1
    static let cardCorner: CGFloat = 24
    /// The sheet is always this much of the screen, and never changes size: the card is drawn inside it. That way the
    /// controls cannot move when the card above them grows or shrinks.
    static let sheetFraction: CGFloat = 0.9
    /// The sheet's height for the instant before the card has measured its content.
    static let firstSheetHeight: CGFloat = 320
    /// How tall the card may be before its content scrolls.
    static let cardMaxFraction: CGFloat = 0.85
    static let cardResize = Animation.snappy(duration: 0.35)
    /// How far up a drag on the controller must go before it counts as opening the card.
    static let openDragDistance: CGFloat = 24
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
                        .onTapGesture { model.cardOpen = true }
                        .gesture(DragGesture(minimumDistance: Chrome.openDragDistance).onEnded { value in
                            if value.translation.height < -Chrome.openDragDistance { model.cardOpen = true }
                        })
                        .accessibilityHidden(model.cardOpen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .sheet(isPresented: $model.cardOpen) {
                PlayerCard(maxHeight: geo.size.height * Chrome.cardMaxFraction)
            }
            .onChange(of: active) { _, isActive in if !isActive { model.cardOpen = false } }
        }
        .ignoresSafeArea(.keyboard)
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

struct PlayerCard: View {
    @EnvironmentObject var model: AppModel
    let maxHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .largeTitle) private var playButtonSide = Chrome.playButtonSide

    /// What the card shows is the engine's own state, read where it is drawn. The only state here is the height of the
    /// card's content, which sets the height of the sheet. The content is anchored to the bottom of the sheet, so when
    /// artwork arrives or goes the sheet's top edge moves and the controls, being at the bottom, do not.
    var body: some View {
        let height = min(contentHeight, maxHeight)
        return Group {
            if contentHeight > maxHeight { ScrollView { content }.scrollBounceBehavior(.basedOnSize) } else { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .presentationDetents([.height(contentHeight > 0 ? height : Chrome.firstSheetHeight)])
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("player-card")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 6)
            if let name = model.activeSession?.name {
                Button { model.playlistLinkTapped() } label: {
                    Text(name).font(.footnote).foregroundStyle(.tint)
                }
                .accessibilityHint("Opens the playlist")
                .accessibilityIdentifier("card-link")
            }
            if let data = model.metadata?.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity).accessibilityHidden(true)
            }
            Text(model.metadata?.title ?? model.transport.nowPlaying).font(.title2.weight(.bold)).lineLimit(2)
            scrubber
            controls
        }
        .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 16)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
            if contentHeight == 0 {            // the first measurement is the card appearing, not a resize
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { contentHeight = newHeight }
            } else {
                withAnimation(reduceMotion ? nil : Chrome.cardResize) { contentHeight = newHeight }
            }
        }
    }

    /// The position slider and the two times. They are drawn on a clock straight from the engine, so they are always the
    /// engine's position. While a finger is on the slider the song is paused and every move seeks the engine itself, so the
    /// slider, the times and the sound can never disagree.
    private var scrubber: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: model.transport.state != .playing)) { _ in
            let position = model.transport.position
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
    }

    private var playButton: some View {
        Button { model.transport.playPause() } label: {
            Image(systemName: model.transport.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                .resizable().frame(width: min(playButtonSide, Chrome.playButtonMaxSide), height: min(playButtonSide, Chrome.playButtonMaxSide))
        }
        .accessibilityLabel(model.transport.state == .playing ? "Pause" : "Play")
    }

    private var nextButton: some View {
        Button { try? model.transport.next() } label: {
            Image(systemName: "forward.fill").font(.title)
                .frame(minWidth: minimumCloudIconTapSize.width, minHeight: minimumCloudIconTapSize.height).contentShape(Rectangle())
        }
        .accessibilityLabel("Next")
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

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
