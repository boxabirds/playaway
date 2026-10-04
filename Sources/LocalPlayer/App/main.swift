import AppKit

// Playlist windows come back after a relaunch, whatever the system's "close windows when quitting" setting is.
// Registered, not set: a person can still override it.
UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": true])

// The playlist document controller must exist before AppKit asks for the shared one.
_ = PlaylistDocumentController()

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)

let services = AppServices()
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
