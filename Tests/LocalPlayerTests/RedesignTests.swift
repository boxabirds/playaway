import XCTest
import AppKit
@testable import LocalPlayer

/// The playlist window redesign (spec 007, prd.simple.hierarchy): emphasis follows use, one control row, a marked
/// playing row, a quiet footer. Layout is checked on a real window at its real sizes.
@MainActor
final class RedesignTests: XCTestCase {
    var app: TestApp!
    let dir = TempDir("redesign")
    var fixture: PlaylistFixture!

    override func setUp() async throws { app = TestApp() }
    override func tearDown() async throws { app.tearDown() }

    func open(_ names: [String] = Fixtures.trackNames) -> (doc: PlaylistDocument, window: PlaylistWindowController) {
        fixture = PlaylistFixture(trackNames: names)
        let doc = app.openSaved(fixture.playlist, at: dir.path("Morning.lplaylist"))
        let window = app.window(of: doc)
        window.window?.setContentSize(NSSize(width: 520, height: 640))
        layout(window)
        return (doc, window)
    }

    func layout(_ controller: PlaylistWindowController) {
        controller.transport.render()
        controller.window?.layoutIfNeeded()
        controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    /// A view's frame in window coordinates, with the origin at the top left (larger y is lower on screen).
    func frame(_ view: NSView, in controller: PlaylistWindowController) -> CGRect {
        let content = controller.window!.contentView!
        let rect = view.convert(view.bounds, to: content)
        return CGRect(x: rect.minX, y: content.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// A control's drawn size: AppKit's frame includes padding around the alignment rect that constraints size.
    func size(_ view: NSView) -> CGSize { view.alignmentRect(forFrame: view.frame).size }

    // MARK: Title and place in the playlist

    func testTitleShowsTheNameWithoutItsExtensionAndKeepsTheFullNameAsTooltip() {
        let (_, window) = open()
        _ = app.services.engine.play(Fixtures.url("tone.wav"))
        spin { window.transport.nowPlayingLabel.stringValue == "tone" }
        XCTAssertEqual(window.transport.nowPlayingLabel.stringValue, "tone")
        XCTAssertEqual(window.transport.nowPlayingLabel.toolTip, "tone.wav")
        XCTAssertEqual(window.transport.nowPlayingLabel.font?.pointSize ?? 0, 24, "the largest text in the window")
    }

    func testNothingPlayingStillSaysSo() {
        let (_, window) = open()
        XCTAssertEqual(window.transport.nowPlayingLabel.stringValue, TransportControlsView.nothingPlayingText)
    }

    func testTrackPositionLineShowsPlaceInThePlaylistOnlyForAPlaylistSession() {
        let (doc, window) = open()
        XCTAssertTrue(window.transport.trackPositionLabel.isHidden, "nothing playing")
        doc.player.play(track: doc.playlist.tracks[1])
        app.services.transport.refresh(); layout(window)
        XCTAssertFalse(window.transport.trackPositionLabel.isHidden)
        XCTAssertEqual(window.transport.trackPositionLabel.stringValue, "Track 2 of 5")
        try? doc.removeTracks(at: [4])
        spin { window.transport.trackPositionLabel.stringValue == "Track 2 of 4" }
        XCTAssertEqual(window.transport.trackPositionLabel.stringValue, "Track 2 of 4", "follows edits")
        _ = app.services.engine.play(Fixtures.url("tone.wav"))      // a single file replaces the session
        app.services.registry.endActive(); app.services.transport.refresh()
        spin { window.transport.trackPositionLabel.isHidden }
        XCTAssertTrue(window.transport.trackPositionLabel.isHidden, "no playlist session, no place in a playlist")
    }

    // MARK: Emphasis follows use

    func testPlayIsTheLargestControlAndPreviousAndNextAreMedium() {
        let (_, window) = open()
        let t = window.transport
        let play = size(t.playPauseButton).height, prev = size(t.previousButton).height, next = size(t.nextButton).height
        let stop = size(t.stopButton).height, shuffle = size(window.modes.shuffleButton).height
        let repeatB = size(window.modes.repeatButton).height, mute = size(t.muteButton).height
        XCTAssertGreaterThanOrEqual(play, 52)
        for other in [prev, next, stop, shuffle, repeatB, mute] { XCTAssertGreaterThan(play, other * 1.3) }
        for medium in [prev, next] {
            XCTAssertGreaterThan(medium, stop, "Previous/Next are bigger than Stop")
            XCTAssertGreaterThan(medium, shuffle, "and bigger than the mode toggles")
        }
        XCTAssertEqual(t.playPauseButton.tintProminence, .primary, "the one filled accent control")
        XCTAssertEqual(t.playPauseButton.bezelStyle, .glass, "a standard button in the system's own style")
        for quiet in [t.previousButton, t.nextButton, t.stopButton, window.modes.shuffleButton, window.modes.repeatButton, t.muteButton] {
            XCTAssertNotEqual(quiet.tintProminence, .primary)
        }
    }

    func testPlayIsCentredInTheWindow() {
        let (_, window) = open()
        let play = frame(window.transport.playPauseButton, in: window)
        XCTAssertEqual(play.midX, window.window!.contentView!.bounds.midX, accuracy: 1.5)
    }

    func testControlRowHoldsModesTransportAndVolumeOnOneLine() {
        let (_, window) = open()
        let t = window.transport
        let play = frame(t.playPauseButton, in: window)
        for view in [t.previousButton, t.nextButton, window.modes.shuffleButton, window.modes.repeatButton, t.muteButton, t.volumeSlider] {
            XCTAssertEqual(frame(view, in: window).midY, play.midY, accuracy: 3, "\(view.accessibilityIdentifier())")
        }
        let shuffle = frame(window.modes.shuffleButton, in: window), repeatB = frame(window.modes.repeatButton, in: window)
        XCTAssertLessThan(repeatB.maxX, frame(t.previousButton, in: window).minX, "modes sit left of the transport")
        XCTAssertGreaterThan(shuffle.minX, 0)
        XCTAssertGreaterThan(frame(t.muteButton, in: window).minX, frame(t.nextButton, in: window).maxX, "volume sits right of it")
        XCTAssertLessThanOrEqual(frame(t.volumeSlider, in: window).width, 100, "volume is a short slider")
    }

    func testVerticalOrderIsTitleThenSeekThenControlsThenList() {
        let (_, window) = open()
        let t = window.transport
        let title = frame(t.nowPlayingLabel, in: window), seek = frame(t.positionSlider, in: window)
        let play = frame(t.playPauseButton, in: window), list = frame(window.scrollView, in: window)
        XCTAssertLessThan(title.maxY, seek.minY)
        XCTAssertLessThan(seek.maxY, play.minY)
        XCTAssertLessThan(play.maxY, list.minY)
        XCTAssertEqual(frame(t.elapsedLabel, in: window).minY, seek.maxY, accuracy: 14, "times sit directly under the seek bar")
        XCTAssertLessThan(frame(t.elapsedLabel, in: window).midX, frame(t.durationLabel, in: window).midX)
    }

    func testStopIsSmallAndSitsBesideTheTitleNotInTheTransportRow() {
        let (_, window) = open()
        let t = window.transport
        let stop = frame(t.stopButton, in: window), title = frame(t.nowPlayingLabel, in: window)
        XCTAssertEqual(stop.midY, title.midY, accuracy: 8)
        XCTAssertGreaterThan(stop.minX, frame(t.playPauseButton, in: window).maxX)
        XCTAssertEqual(stop.maxX, window.window!.contentView!.bounds.width - 20, accuracy: 6, "at the right edge of the content")
        XCTAssertLessThanOrEqual(size(t.stopButton).height, 28)
    }

    func testControlRowFitsAtTheMinimumWindowWidthWithoutOverlap() {
        let (_, window) = open()
        window.window?.setContentSize(NSSize(width: window.window!.minSize.width, height: 600))
        layout(window)
        let t = window.transport
        let views: [NSView] = [window.modes.shuffleButton, window.modes.repeatButton, t.previousButton, t.playPauseButton,
                               t.nextButton, t.muteButton, t.volumeSlider]
        let frames = views.map { frame($0, in: window) }
        let bounds = window.window!.contentView!.bounds
        for (index, rect) in frames.enumerated() {
            XCTAssertTrue(bounds.insetBy(dx: 4, dy: 0).contains(CGRect(x: rect.minX, y: bounds.minY + 1, width: rect.width, height: 1)), "\(index) inside the window")
            if index + 1 < frames.count { XCTAssertLessThanOrEqual(rect.maxX, frames[index + 1].minX + 0.5, "\(index) does not overlap the next") }
        }
        XCTAssertGreaterThan(t.positionSlider.frame.width, 150, "the seek bar still has room")
    }

    // MARK: Shuffle and Repeat are icons that show their state

    func testModesAreIconOnlyAndSayTheirStateInTheTooltipAndAccessibilityValue() {
        let (_, window) = open()
        let modes = window.modes
        for button in [modes.shuffleButton, modes.repeatButton] {
            XCTAssertEqual(button.title, "")
            XCTAssertEqual(button.imagePosition, .imageOnly)
        }
        XCTAssertEqual(modes.shuffleButton.toolTip, "Shuffle: Off")
        XCTAssertEqual(modes.repeatButton.toolTip, "Repeat: Off")
        var seen: [String] = []
        for _ in 0..<3 { modes.repeatPressed(); seen.append(modes.repeatButton.toolTip ?? "") }
        XCTAssertEqual(seen, ["Repeat: All", "Repeat: One", "Repeat: Off"])
        modes.shufflePressed()
        XCTAssertEqual(modes.shuffleButton.toolTip, "Shuffle: On")
        XCTAssertEqual(modes.shuffleButton.accessibilityValue() as? String, "on")
    }

    func testModesUseTheAccentOnlyWhileOnAndRepeatOneHasItsOwnGlyph() {
        let (_, window) = open()
        let modes = window.modes
        XCTAssertEqual(modes.shuffleButton.contentTintColor, .secondaryLabelColor)
        XCTAssertEqual(modes.repeatButton.contentTintColor, .secondaryLabelColor)
        modes.shufflePressed()
        XCTAssertEqual(modes.shuffleButton.contentTintColor, .controlAccentColor)
        XCTAssertEqual(modes.shuffleButton.state, .on)
        XCTAssertTrue(modes.shuffleButton.isBordered, "shape as well as colour: the on state draws the pressed look")
        XCTAssertFalse(window.modes.repeatButton.isBordered, "off draws nothing but the grey glyph")
        modes.repeatPressed()
        XCTAssertEqual(modes.repeatButton.contentTintColor, .controlAccentColor)
        let all = modes.repeatButton.image
        modes.repeatPressed()
        XCTAssertEqual(modes.repeatButton.contentTintColor, .controlAccentColor)
        XCTAssertNotEqual(modes.repeatButton.image?.tiffRepresentation, all?.tiffRepresentation, "One looks different from All")
    }

    // MARK: Volume is small and grey

    func testVolumeIsAShortGreySliderBesideAMuteButton() {
        let (_, window) = open()
        XCTAssertEqual(window.transport.volumeSlider.trackFillColor, .secondaryLabelColor)
        XCTAssertEqual(window.transport.volumeSlider.controlSize, .small)
        XCTAssertEqual(window.transport.muteButton.contentTintColor, .secondaryLabelColor)
    }

    // MARK: The list

    func testListHasNoBorderNoStripesAndNoEmptyStripes() {
        let (_, window) = open()
        XCTAssertFalse(window.tableView.usesAlternatingRowBackgroundColors)
        XCTAssertEqual(window.scrollView.borderType, .noBorder)
    }

    func testPlayingRowIsMarkedAndMovesWithPlaybackAndShowsPausedWhenPaused() {
        let (doc, window) = open()
        func marker(_ row: Int) -> TrackCellView.Marker {
            (window.tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as! TrackCellView).marker
        }
        for row in 0..<5 { XCTAssertEqual(marker(row), .none) }
        window.playRow(1)
        spin { marker(1) == .playing }
        XCTAssertEqual((0..<5).map(marker), [.none, .playing, .none, .none, .none])
        let cell = window.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as! TrackCellView
        XCTAssertTrue(cell.accessibilityLabel()?.hasSuffix(", playing") == true, "said in words, not only shown")
        XCTAssertGreaterThan(cell.titleWeight.rawValue, NSFont.Weight.regular.rawValue)
        try? app.services.transport.pause()
        spin { marker(1) == .paused }
        XCTAssertEqual(marker(1), .paused)
        doc.player.next()
        spin { marker(2) == .paused || marker(2) == .playing }
        XCTAssertEqual(marker(1), .none, "the marker moved on")
    }

    /// Found by the end-to-end test: the marker kept the hazard icon's "Could not be played" label.
    func testPlayingAndPausedMarkersAreNeverAnnouncedAsCouldNotBePlayed() {
        let (_, window) = open()
        window.playRow(1)
        let cell = window.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as! TrackCellView
        spin { cell.marker == .playing }
        XCTAssertEqual(cell.glyphDescription, "Playing")
        try? app.services.transport.pause()
        spin { cell.marker == .paused }
        XCTAssertEqual(cell.glyphDescription, "Paused")
        fixture.deleteFile(at: 3)
        window.playRow(3)
        let hazard = window.tableView.view(atColumn: 0, row: 3, makeIfNecessary: true) as! TrackCellView
        XCTAssertEqual(hazard.glyphDescription, "Could not be played")
    }

    func testPlayingMarkerFromTheScriptRouteMatchesTheUIRoute() throws {
        let actions = AppActions(services: app.services)
        actions.isReady = { true }
        let (_, window) = open()
        try actions.playTrack(3, inPlaylist: "Morning")
        func marker(_ row: Int) -> TrackCellView.Marker {
            (window.tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as! TrackCellView).marker
        }
        spin { marker(2) == .playing }
        XCTAssertEqual((0..<5).map(marker), [.none, .none, .playing, .none, .none])
    }

    func testStoppingClearsTheMarker() {
        let (_, window) = open()
        window.playRow(0)
        try? app.services.transport.stop()
        let cell = window.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as! TrackCellView
        spin { cell.marker == .none }
        XCTAssertEqual(cell.marker, .none)
    }

    func testAnUnplayableTrackShowsTheHazardNotThePlayingMarker() {
        let (_, window) = open()
        fixture.deleteFile(at: 2)
        window.playRow(2)
        let cell = window.tableView.view(atColumn: 0, row: 2, makeIfNecessary: true) as! TrackCellView
        XCTAssertTrue(cell.showsHazard)
        XCTAssertEqual(cell.marker, .none)
    }

    // MARK: Footer

    func testFooterShowsAddOnTheLeftCountInTheMiddleAndRemoveOnTheRight() {
        let (doc, window) = open()
        XCTAssertEqual(window.countLabel.stringValue, "5 tracks")
        let add = frame(window.addButton, in: window), count = frame(window.countLabel, in: window), remove = frame(window.removeButton, in: window)
        XCTAssertLessThan(add.maxX, count.minX)
        XCTAssertLessThan(count.maxX, remove.minX)
        XCTAssertGreaterThan(add.minY, frame(window.scrollView, in: window).maxY - 1, "below the list")
        XCTAssertEqual(window.removeButton.title, "")
        XCTAssertEqual(window.removeButton.accessibilityLabel(), "Remove")
        try? doc.removeTracks(at: [1, 2, 3, 4])
        XCTAssertEqual(window.countLabel.stringValue, "1 track")
        try? doc.removeTracks(at: [0])
        XCTAssertTrue(window.countLabel.isHidden, "the empty hint says it already")
    }

    func testListGetsTheHeightTheControlsGaveUp() {
        let (_, window) = open()
        let list = frame(window.scrollView, in: window)
        let content = window.window!.contentView!.bounds
        XCTAssertGreaterThan(list.height / content.height, 0.5, "the list is more than half of the window")
    }

    // MARK: The manifest check still passes

    func testManifestRecordsTheNewElementsWithTheirJobs() throws {
        let manifest = try UIManifest(data: Data(contentsOf: bundledManifestURL))
        let entries = Dictionary(uniqueKeysWithValues: manifest.entries[.playlist]!.map { ($0.elementID, $0.job) })
        XCTAssertEqual(entries["playback.track_position"], .playPlaylist)
        XCTAssertEqual(entries["playlist.count"], .managePlaylists)
    }

    func testEveryVisibleElementIsIdentifiedInEveryState() throws {
        let manifest = try UIManifest(data: Data(contentsOf: bundledManifestURL))
        var observed: [WindowState: [ObservedElement]] = [:]
        for state in WindowState.allCases { observed[state] = try UICheckMode(fixtureAudio: Fixtures.trackNames.map { Fixtures.url($0) }).visibleElements(in: state) }
        let violations = ManifestChecker.check(manifest: manifest, kind: .playlist, observed: observed)
        XCTAssertTrue(violations.isEmpty, violations.map(\.description).joined(separator: "\n"))
        XCTAssertTrue(observed[.playing]!.contains { $0.id == "playback.track_position" })
        XCTAssertFalse(observed[.idle]!.contains { $0.id == "playback.track_position" })
    }
}
