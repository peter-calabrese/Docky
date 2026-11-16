import AppKit

// Serializes Apple Events off the UI thread; no Dock restarts or simulated key presses.
actor DockAutomation {
    func execute(_ source: String) throws -> String {
        var details: NSDictionary?
        guard let script = NSAppleScript(source: "with timeout of 5 seconds\n" + source + "\nend timeout") else {
            throw NSError(domain: "Docky", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create Dock command."])
        }
        let result = script.executeAndReturnError(&details)
        if let details {
            throw NSError(domain: "Docky", code: 2, userInfo: [NSLocalizedDescriptionKey:
                (details[NSAppleScript.errorMessage] as? String ?? "Dock command failed.") + " Check Docky’s Automation permission for System Events, then try again."])
        }
        return result.stringValue ?? ""
    }

    func read() throws -> Bool {
        try execute("tell application \"System Events\" to get autohide of dock preferences") == "true"
    }

    func write(_ hidden: Bool) throws {
        _ = try execute("tell application \"System Events\" to set autohide of dock preferences to \(hidden ? "true" : "false")")
    }
}

