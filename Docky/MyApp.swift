import SwiftUI
import AppKit

@main
struct DockyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Docky", systemImage: "dock.rectangle") {
            ContentView(controller: delegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}
