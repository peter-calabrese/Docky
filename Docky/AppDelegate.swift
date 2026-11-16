import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DockController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await controller.stop()
            NSApp.reply(toApplicationShouldTerminate: controller.error == nil)
        }
        return .terminateLater
    }
}
