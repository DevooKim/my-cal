import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let store = CalendarStore()
    private var statusController: StatusItemController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(store: store, settings: settings) { [weak self] in
            self?.showSettings()
        }
        Task { await store.requestAccess() }
    }

    private func showSettings() {
        statusController?.closePopover()
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, store: store))
            let window = NSWindow(contentViewController: host)
            window.title = "MyCal 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
