import PlayawayCore
import AppKit

/// The whole launch runs on the main actor, which is where AppKit and the shared services live.
@MainActor
func launchApplication() {
    // Playlist windows come back after a relaunch, whatever the system's "close windows when quitting" setting is.
    // Registered, not set: a person can still override it.
    UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": true])

    // The playlist document controller must exist before AppKit asks for the shared one.
    _ = PlaylistDocumentController()

    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)

    // The end-to-end tests point a debug build at a stand-in iCloud folder; a release build always uses the real one.
    let cloudStandIn = CloudStandIn.setting()
    let services = AppServices(cloudRoot: CloudStandIn.cloudRoot(for: cloudStandIn) ?? { CloudFolder.documentsOnThisDevice() },
                               cloudSongs: CloudStandIn.cloudSongs(for: cloudStandIn))
    if let isUbiquitous = CloudStandIn.isUbiquitous(for: cloudStandIn) { services.cloud.isUbiquitous = isUbiquitous }
    AppServices.shared = services
    services.connect(controller: PlaylistDocumentController.current)
    delegate.services = services
    delegate.updater = UpdaterController(configuration: UpdateConfiguration.fromBundle())
    delegate.actions = AppActions(services: services)
    delegate.actions.updater = delegate.updater

    if let mode = CommandLineMode.parse(CommandLine.arguments) {
        exit(CommandLineMode.run(mode, application: application, services: services))
    }

    application.run()
}

MainActor.assumeIsolated { launchApplication() }
