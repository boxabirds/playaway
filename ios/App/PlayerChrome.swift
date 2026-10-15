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
    /// Room for the system's drag indicator above the card's content.
    static let dragIndicatorRoom: CGFloat = 28
    /// The most of the screen the card may use before it scrolls.
    static let cardMaxScreenFraction: CGFloat = 0.9
    /// How far up a drag on the controller must go before it counts as opening the card.
    static let openDragDistance: CGFloat = 24
}

/// The floating controller at the bottom, and the player card, which is a standard system sheet: the system draws the
/// drag indicator, follows the finger, decides when to settle open or closed and rubber-bands. Nothing here tracks a
/// drag. Tapping the controller or dragging it up opens the card.
struct PlayerChrome: View {
    @EnvironmentObject var model: AppModel
    @State private var cardContentHeight: CGFloat = 0
    /// The sheet's heights while it moves from one to another, and the one it is at. A sheet whose height simply changes
    /// snaps; selecting between two heights inside an animation makes the system slide its top edge.
    @State private var detentHeights: [CGFloat] = []
    @State private var selectedDetent: PresentationDetent = .large
    @State private var settledHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let active = model.transport.state != .idle || model.resumePoint != nil
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
                PlayerCard(contentHeight: $cardContentHeight, scrolls: cardHeight(in: geo) >= geo.size.height * Chrome.cardMaxScreenFraction)
                    .presentationDetents(Set(detentHeights.map { PresentationDetent.height($0) }.ifEmpty([.large])), selection: $selectedDetent)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.regularMaterial)
                    .onAppear { resize(to: cardHeight(in: geo), in: geo, animated: false) }
                    .onChange(of: cardHeight(in: geo)) { _, new in resize(to: new, in: geo, animated: true) }
            }
            .onChange(of: model.cardOpen) { _, open in if open { settledHeight = nil } }
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

    /// The card is as tall as its content, so the sheet is too; it grows and shrinks with the content (artwork arriving)
    /// as the system resizes the sheet from its bottom edge.
    private func cardHeight(in geo: GeometryProxy) -> CGFloat {
        let content = cardContentHeight > 0 ? cardContentHeight + Chrome.dragIndicatorRoom : geo.size.height * 0.4
        return min(content, geo.size.height)
    }

    /// Moves the sheet to a new height. The old and new heights are both offered while the system slides between them,
    /// and the old one is dropped when the slide has finished.
    private func resize(to height: CGFloat, in geo: GeometryProxy, animated: Bool) {
        let tall = height >= geo.size.height * Chrome.cardMaxScreenFraction
        let target: PresentationDetent = tall ? .large : .height(height)
        guard let old = settledHeight, animated, !reduceMotion, abs(old - height) > 1 else {
            detentHeights = tall ? [] : [height]
            selectedDetent = target
            settledHeight = height
            return
        }
        detentHeights = tall ? [old] : [old, height]
        settledHeight = height
        withAnimation(.snappy(duration: 0.35)) {
            selectedDetent = target
        } completion: {
            detentHeights = tall ? [] : [height]
        }
    }
}

extension Array {
    fileprivate func ifEmpty(_ fallback: [Element]) -> [Element] { isEmpty ? fallback : self }
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
    @Binding var contentHeight: CGFloat
    let scrolls: Bool
    @State private var scrubPosition: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var playButtonSide = Chrome.playButtonSide

    var body: some View {
        // The content is anchored to the bottom of the sheet, so when artwork arrives or goes the top of the sheet moves
        // and the controls stay where they are. It scrolls only when it is taller than the screen allows.
        Group {
            if scrolls {
                ScrollView { content }.scrollBounceBehavior(.basedOnSize)
            } else {
                content.frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityIdentifier("player-card")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    }

    private var scrubber: some View {
        let shown = scrubPosition ?? model.resumePoint?.positionSeconds ?? model.transport.position
        let resting = model.resumePoint != nil
        return VStack(spacing: 2) {
            // The song pauses while a finger is on the slider and seeks once when it lifts, so nothing is heard from the
            // places the slider passes through and no stretch is played twice.
            Slider(value: Binding(get: { shown }, set: { scrubPosition = $0 }),
                   in: 0...max(model.transport.duration, 1), step: Chrome.scrubberStep) { editing in
                if editing { model.transport.beginScrub() }
                else { try? model.transport.endScrub(toSeconds: scrubPosition ?? model.transport.position); scrubPosition = nil }
            }
            .accessibilityLabel("Playback position")
            .accessibilityValue(resting ? "" : "\(TransportViewModel.formatTime(shown)) of \(TransportViewModel.formatTime(model.transport.duration))")
            .disabled(resting)
            HStack {
                Text(TransportViewModel.formatTime(shown))
                Spacer()
                Text(resting ? "-:--" : "-" + TransportViewModel.formatTime(max(model.transport.duration - shown, 0)))
            }
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
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
