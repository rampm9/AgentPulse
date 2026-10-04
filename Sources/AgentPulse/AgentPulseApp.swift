import SwiftUI
import AppKit
import Combine

enum PopoverMetrics {
    static let width: CGFloat = 372
    static let height: CGFloat = 640
}

extension Notification.Name {
    /// `true` while a menu inside the panel is open, so the panel does not dismiss itself.
    static let agentPulseHoldPopover = Notification.Name("agentPulseHoldPopover")
}

@main
struct AgentPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = StateStore.shared
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    private var cancellable: AnyCancellable?
    /// Transient popovers close on the same click that hits the status item, which would reopen them.
    private var closedAt: Date?
    
    private var refreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        startUsageRefresh()
    }

    func startUsageRefresh() {
        store.refreshUsage()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let seconds = max(60, self?.store.refreshIntervalSeconds ?? 900)
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                self?.store.refreshUsage()
            }
        }
    }
    
    func setupMenu() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: PopoverMetrics.width, height: PopoverMetrics.height)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let hosting = NSHostingController(rootView: PopoverView(store: store))
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hosting
        self.popover = popover
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(holdPopover(_:)),
            name: .agentPulseHoldPopover,
            object: nil
        )

        cancellable = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshStatusItem()
                }
            }
    }

    func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: store.statusSymbolName, accessibilityDescription: "AgentPulse")
        image?.isTemplate = true
        button.image = image
        if store.showPercentageInBar {
            button.title = " \(store.fullestLimitPercent)%"
        } else {
            button.title = ""
        }
    }
    
    func popoverDidClose(_ notification: Notification) {
        closedAt = Date()
    }

    @objc func holdPopover(_ notification: Notification) {
        let hold = (notification.object as? Bool) ?? false
        popover?.behavior = hold ? .applicationDefined : .transient
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu(from: button)
            return
        }

        if let closedAt, Date().timeIntervalSince(closedAt) < 0.35 {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            store.refreshSubscriptions()
            store.refreshUsage()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showStatusMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit AgentPulse", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc func quit(_ sender: AnyObject?) {
        NSApp.terminate(sender)
    }
}
