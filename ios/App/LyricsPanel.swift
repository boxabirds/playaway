import SwiftUI
import PlayawayCore

/// The lyrics above the controls when the card is pulled up. The current line is read from the engine's position on
/// every frame; nothing here remembers where the song is.
struct LyricsPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack {                                   // one element, so the identifier lands on the panel itself
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
            case .generating(let stage):
                VStack(spacing: 12) {
                    ProgressView()
                    Text(stage + "…").font(.subheadline).foregroundStyle(.secondary)
                    Button("Cancel") { model.lyrics.cancel() }.font(.caption)
                }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lyrics-panel")
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
