import SwiftUI
import PlayawayCore

/// The floating controller's footprint at the bottom of the screen, so lists can scroll clear of it.
enum PlayerBar {
    static let height: CGFloat = 64
    static let bottomMargin: CGFloat = 4
    static let gapAboveIt: CGFloat = 8
    static let inset: CGFloat = height + bottomMargin + gapAboveIt
}

private enum Chrome {
    static let artworkSide: CGFloat = 44
    static let cardCorner: CGFloat = 24
    static let settleThreshold: CGFloat = 0.5
    static let cardFirstFrameFraction: CGFloat = 0.4
    static let playButtonSide: CGFloat = 76
    static let scrubberStep: Double = 1
}

/// Floating controller at the bottom plus the card that slides up over the screen. The card follows the finger and
/// always settles fully open or fully closed.
struct PlayerChrome: View {
    @EnvironmentObject var model: AppModel
    @State private var drag: CGFloat = 0
    @State private var cardContentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let active = model.transport.state != .idle || model.resumePoint != nil
            let hasArtwork = model.metadata?.artworkData != nil
            let cardHeight = cardContentHeight > 0 ? min(cardContentHeight, geo.size.height) : geo.size.height * Chrome.cardFirstFrameFraction
            let progress = max(0, min(1, (model.cardOpen ? 1 : 0) - drag / max(cardHeight, 1)))
            ZStack(alignment: .bottom) {
                if active {
                    if progress > 0 { Color.black.opacity(0.25 * progress).ignoresSafeArea().onTapGesture { close() } }
                    if progress > 0 {
                        PlayerCard(contentHeight: $cardContentHeight)
                            .frame(height: cardHeight, alignment: .bottom)
                            .offset(y: (cardHeight + geo.safeAreaInsets.bottom) * (1 - progress))
                            .gesture(dragGesture(cardHeight))
                            .transition(.move(edge: .bottom))
                    }
                    FloatingController()
                        .opacity(1 - progress)
                        .gesture(dragGesture(cardHeight))
                        .onTapGesture { open() }
                        .allowsHitTesting(progress < 1)
                        .accessibilityHidden(progress == 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.snappy(duration: 0.25), value: model.cardOpen)
            .animation(.snappy(duration: 0.25), value: hasArtwork)
        }
        .ignoresSafeArea(.keyboard)
        .alert("This playlist is no longer available", isPresented: $model.showUnsavedOffer) {
            Button("Save Playlist…") { model.saveUnsavedPlaylist() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Its file was deleted or moved. You can save its songs as a new playlist file.") }
        .alert("Playlist", isPresented: Binding(get: { model.failureMessage != nil }, set: { if !$0 { model.failureMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.failureMessage ?? "") }
    }

    private func open() { withAnimation(.snappy(duration: 0.25)) { model.cardOpen = true } }
    private func close() { withAnimation(.snappy(duration: 0.25)) { model.cardOpen = false } }

    private func dragGesture(_ height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag = $0.translation.height }
            .onEnded { value in
                let final = (model.cardOpen ? 1 : 0) - value.translation.height / max(height, 1)
                withAnimation(.snappy(duration: 0.25)) {
                    model.cardOpen = final > Chrome.settleThreshold
                    drag = 0
                }
            }
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
        .frame(height: PlayerBar.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 8).padding(.bottom, PlayerBar.bottomMargin)
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
    @State private var scrubPosition: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            if let name = model.activeSession?.name {
                Button { model.playlistLinkTapped() } label: {
                    Text(name).font(.footnote).foregroundStyle(.tint)
                }
                .accessibilityHint("Opens the playlist")
            }
            if let data = model.metadata?.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity).accessibilityHidden(true)
            }
            Text(model.metadata?.title ?? model.transport.nowPlaying).font(.title2.weight(.bold)).lineLimit(2)
            scrubber
            controls
        }
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 24)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Chrome.cardCorner, topTrailingRadius: Chrome.cardCorner)
                .fill(.regularMaterial).ignoresSafeArea(edges: .bottom)
        }
        .accessibilityIdentifier("player-card")
    }

    private var scrubber: some View {
        let shown = scrubPosition ?? model.resumePoint?.positionSeconds ?? model.transport.position
        let resting = model.resumePoint != nil
        return VStack(spacing: 2) {
            Slider(value: Binding(get: { shown }, set: { scrubPosition = $0; model.scrubber.scrub(to: $0) }),
                   in: 0...max(model.transport.duration, 1), step: Chrome.scrubberStep) { editing in
                if !editing, let last = scrubPosition { model.scrubber.finish(at: last); scrubPosition = nil }
            }
            .accessibilityLabel("Playback position")
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
        HStack {
            Button { model.settings.toggleShuffle() } label: {
                Image(systemName: "shuffle").foregroundStyle(model.settings.shuffleOn ? Color.accentColor : .secondary)
            }
            .accessibilityLabel("Shuffle").accessibilityValue(model.settings.shuffleOn ? "On" : "Off")
            Spacer()
            Button { try? model.transport.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                .accessibilityLabel("Previous")
            Spacer()
            Button { model.transport.playPause() } label: {
                Image(systemName: model.transport.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                    .resizable().frame(width: Chrome.playButtonSide, height: Chrome.playButtonSide)
            }
            .accessibilityLabel(model.transport.state == .playing ? "Pause" : "Play")
            Spacer()
            Button { try? model.transport.next() } label: { Image(systemName: "forward.fill").font(.title) }
                .accessibilityLabel("Next")
            Spacer()
            Button { model.settings.cycleRepeat() } label: {
                Image(systemName: model.settings.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(model.settings.repeatMode == .off ? Color.secondary : Color.accentColor)
            }
            .accessibilityLabel("Repeat").accessibilityValue(repeatSpoken)
        }
        .font(.title3).buttonStyle(.plain)
    }

    private var repeatSpoken: String {
        switch model.settings.repeatMode { case .off: "Off"; case .all: "All"; case .one: "One" }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
