import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: DockController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Docky", systemImage: "dock.rectangle")
                .font(.title2.bold())
            Text("Show the Dock when there’s room.")
                .foregroundStyle(.secondary)
            Toggle("Smart Dock", isOn: Binding(
                get: { controller.enabled },
                set: { value in Task { await controller.setEnabled(value) } }
            ))
            .disabled(controller.busy)
            Label(controller.status, systemImage: controller.enabled ? "checkmark.circle" : "pause.circle")
                .font(.callout)
            if let error = controller.error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            if controller.hasSavedSetting && !controller.enabled {
                Text("A saved Dock setting is available to restore.")
                    .font(.callout)
                Button("Restore Original Dock Setting") {
                    Task { await controller.stop() }
                }.disabled(controller.busy)
            }
            HStack {
                Text("Window gap (px)")
                Spacer()
                TextField("0", value: Binding(
                    get: { controller.windowGap },
                    set: { controller.windowGap = min(200, max(0, $0)) }
                ), format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.trailing)
                .frame(width: 55)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Window gap in pixels")
            }
            Text("Enter your window manager’s outer gap (0–200). Docky will hide the Dock before the window crosses that gap and preserve it when expanding.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Expand windows into freed Dock space", isOn: $controller.expandWindowsIntoDockSpace)
                .font(.callout)
            Text("Keeps the Dock hidden while any on-screen app window reaches its reserved space. Optional expansion affects only the selected window, including half-screen windows.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Docky needs Accessibility to read window positions and Automation permission for System Events to change Dock auto-hide.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open Accessibility Settings") { controller.openAccessibility() }
            Button("Open Automation Settings") { controller.openAutomation() }
            Text("When hidden, move your pointer to the screen edge to reveal the Dock. Your original setting is restored when Docky is disabled or quits.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Quit Docky") { NSApplication.shared.terminate(nil) }
        }
        .padding(20)
        .frame(width: 330)
    }
}
