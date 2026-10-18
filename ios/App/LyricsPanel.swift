import SwiftUI
import PlayawayCore

/// The lyrics section below the controls. A "Lyrics" disclosure row heads it, as the system's own folding sections
/// are headed: the chevron points right when the section is folded and down when it is open, and the row is the
/// button. The current line is read from the engine's position on every frame; nothing here remembers where the
/// song is.
struct LyricsPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {                       // one element, so the identifier lands on the panel itself
            if model.lyrics.status != .off { header }
            if model.lyrics.status == .off || model.lyrics.settings.panelShown { section }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lyrics-panel")
    }

    private var header: some View {
        let shown = model.lyrics.settings.panelShown
        return Button { model.lyrics.settings.panelShown.toggle() } label: {
            HStack {
                Text("Lyrics").font(.headline).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(shown ? 90 : 0))
                    .animation(reduceMotion ? nil : .easeInOut(duration: Chrome.cardResizeDuration), value: shown)
            }
            .frame(minHeight: Chrome.lyricsHeaderHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lyrics")
        .accessibilityValue(shown ? "Expanded" : "Collapsed")
        .accessibilityHint(shown ? "Hides the lyrics" : "Shows the lyrics")
        .accessibilityIdentifier("lyrics-disclosure")
        .keyboardShortcut("l", modifiers: .command)
    }

    private var section: some View {
        VStack {
            switch model.lyrics.status {
            case .off:
                message("Lyrics are an experiment.", detail: "Turn them on under Experiments on the Playlists screen.")
            case .none:
                VStack(spacing: 12) {
                    Text("No lyrics yet for this song.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Make Lyrics") { model.lyrics.makeLyrics() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("lyrics-make")
                    Text("They are transcribed on this iPhone by \(model.lyrics.settings.engine.displayName) and may be wrong.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            case .generating(let stage, let share, let since):
                LyricsProgress(stage: stage, share: share, since: since) { model.lyrics.cancel() }
            case .failed(let why):
                VStack(spacing: 12) {
                    message("The lyrics could not be made.", detail: why)
                    Button("Try Again") { model.lyrics.makeLyrics() }.font(.caption)
                }
            case .ready:
                if let sheet = model.lyrics.sheet { LyricsList(sheet: sheet) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(detail).font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .accessibilityIdentifier("lyrics-status")
    }
}

/// What is being done, how far it has got, how long it has taken and a guess at what is left. Whisper on a phone can
/// take minutes for one song, so a bare spinner is not enough.
private struct LyricsProgress: View {
    let stage: String
    let share: Double
    let since: Date
    let cancel: () -> Void

    /// No estimate until this much is done; before that the rate means nothing.
    private static let estimateAfter = 0.05

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let spent = context.date.timeIntervalSince(since)
            VStack(spacing: 10) {
                ProgressView(value: min(max(share, 0), 1))
                    .accessibilityIdentifier("lyrics-progress")
                HStack {
                    Text("\(stage)… \(Int(share * 100))%").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.describe(spent: spent, share: share)).font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
                Button("Cancel", action: cancel).font(.caption)
            }
            .padding(.horizontal)
        }
    }

    static func describe(spent: TimeInterval, share: Double) -> String {
        let spentText = "\(TransportViewModel.formatTime(spent)) so far"
        guard share > estimateAfter else { return spentText }
        let left = spent / share - spent
        return spentText + ", about \(TransportViewModel.formatTime(left)) left"
    }
}

/// The lines, scrolling with the song. Tapping a line seeks to it.
private struct LyricsList: View {
    @EnvironmentObject var model: AppModel
    let sheet: LyricSheet
    @State private var userScrolledAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tick: TimeInterval = 0.1

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.tick, paused: model.transport.state != .playing)) { _ in
            let position = model.transport.displayPosition
            let current = LyricSync.currentLineIndex(in: sheet.lines, at: position)
            let instrumental = LyricSync.isInstrumental(in: sheet.lines, at: position)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Text("Transcribed on this iPhone by \(sheet.engine.displayName). May be wrong.")
                            .font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 4)
                            .accessibilityIdentifier("lyrics-note")
                        ForEach(sheet.lines) { line in
                            let isCurrent = line.id == current
                            let doubtful = (line.confidence ?? 1) < LyricsCoordinator.lowConfidence
                            Text(line.text)
                                .font(.title3.weight(isCurrent ? .bold : .semibold))
                                .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                .opacity(doubtful && !isCurrent ? 0.55 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { try? model.transport.seek(toSeconds: line.start) }
                                .id(line.id)
                                .accessibilityIdentifier("lyrics-line-\(line.id)")
                                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                                .accessibilityHint(doubtful ? "Low confidence" : "")
                        }
                        if instrumental {
                            Text("· · ·").font(.title3).foregroundStyle(.tertiary).accessibilityIdentifier("lyrics-instrumental")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting || phase == .decelerating { userScrolledAt = Date() }
                }
                .onChange(of: current) { _, line in
                    guard let line else { return }
                    if let at = userScrolledAt, Date().timeIntervalSince(at) < LyricsCoordinator.userScrollHold { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { proxy.scrollTo(line, anchor: .center) }
                }
                .onAppear { if let line = current { proxy.scrollTo(line, anchor: .center) } }
            }
        }
    }
}
