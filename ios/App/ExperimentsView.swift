import SwiftUI
import PlayawayCore
import PlayawayLyrics

/// Switches for features that are being tried out. Off by default; nothing here changes the app until it is turned on.
struct ExperimentsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show lyrics", isOn: Binding(get: { model.lyrics.settings.enabled }, set: { model.lyrics.settings.enabled = $0 }))
                        .accessibilityIdentifier("lyrics-enabled")
                    Picker("Engine", selection: Binding(get: { model.lyrics.settings.engine }, set: { model.lyrics.settings.engine = $0 })) {
                        ForEach(LyricEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Separate the vocals first", isOn: Binding(get: { model.lyrics.settings.separateVocals }, set: { model.lyrics.settings.separateVocals = $0 }))
                } header: { Text("Lyrics") } footer: {
                    Text("Lyrics are transcribed on this iPhone from the song itself. Pull the player up to see them. They are machine guesses and may be wrong.")
                }
                Section("Models") {
                    modelRow(name: ModelDownload.mdxVocals.name, bytes: ModelDownload.mdxVocals.bytes,
                             installed: model.lyrics.separatorInstalled, progress: model.lyrics.downloads[ModelDownload.mdxVocals.name]) {
                        model.lyrics.installSeparator()
                    }
                    modelRow(name: "Whisper (\(WhisperKitTranscriber.defaultModel))", bytes: 626_000_000,
                             installed: model.lyrics.whisperInstalled, progress: model.lyrics.downloads["Whisper"]) {
                        model.lyrics.installWhisper()
                    }
                    Text("Apple Speech needs no download; the system fetches its model the first time.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Measuring") {
                    Button("Benchmark the Current Song") { model.lyrics.benchmarkCurrentSong() }
                        .disabled(model.transport.state == .idle)
                    if let report = model.lyrics.benchmarkReport {
                        Text("Report saved as \(report.lastPathComponent) in Playaway's folder in Files.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Clear Made Lyrics", role: .destructive) { model.lyrics.clearCache() }
                }
            }
            .navigationTitle("Experiments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func modelRow(name: String, bytes: Int64, installed: Bool, progress: Double?, install: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(installed ? "Downloaded" : "\(bytes / 1_000_000) MB").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let progress {
                ProgressView(value: progress).frame(width: 80)
            } else if !installed {
                Button("Download", action: install)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Downloaded")
            }
        }
    }
}
