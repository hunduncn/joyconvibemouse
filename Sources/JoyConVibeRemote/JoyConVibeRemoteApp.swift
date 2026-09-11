import AppKit
import Combine
import SwiftUI

@main
struct JoyConVibeRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settings: RemoteSettings?
    private var model: AppModel?
    private var statusCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let settings = RemoteSettings()
        let model = AppModel(settings: settings)
        self.settings = settings
        self.model = model

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(
            width: StatusMenuView.panelWidth,
            height: StatusMenuView.initialHeight
        )
        let hostingController = NSHostingController(
            rootView: StatusMenuView(
                model: model,
                settings: settings,
                onPreferredHeightChange: { [weak self] height in
                    self?.updatePopoverHeight(height)
                }
            )
        )
        popover.contentViewController = hostingController
        hostingController.view.frame = NSRect(
            origin: .zero,
            size: popover.contentSize
        )
        // Build the SwiftUI hierarchy during app launch so clicking the menu
        // bar icon only has to position an already-laid-out panel.
        hostingController.view.layoutSubtreeIfNeeded()

        model.onShowStatus = { [weak self] in
            self?.showPopover()
        }
        statusCancellable = model.$status.sink { [weak self] status in
            self?.updateStatusItem(for: status)
        }

        model.start()
        if !model.accessibilityTrusted {
            showPopover()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Permission probing is not required to present the panel. Refresh it
        // on the next run-loop turn so the click responds immediately.
        DispatchQueue.main.async { [weak model] in
            model?.refreshPermissions()
        }
    }

    private func updatePopoverHeight(_ height: CGFloat) {
        let preferredSize = NSSize(width: StatusMenuView.panelWidth, height: height)
        guard abs(popover.contentSize.height - height) > 0.5 else { return }
        popover.contentSize = preferredSize
        popover.contentViewController?.preferredContentSize = preferredSize
    }

    private func updateStatusItem(for status: RemoteStatus) {
        let image = NSImage(
            systemSymbolName: status.symbolName,
            accessibilityDescription: status.title
        )
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = "JoyCon Vibe Remote · \(status.title)"
    }
}
