import Foundation

@MainActor
final class ClaudeWhip {
    static let messages = [
        "FASTER",
        "GO FASTER",
        "Faster CLANKER",
        "Work FASTER",
        "Speed it up clanker",
        "You're too slow",
        "THINK HARDER",
        "I didn't slap my laptop for you to be slow",
    ]

    static func whip() {
        if isClaudeCodeRunning() {
            sendInterruptAndMessage()
        } else {
            launchClaudeInGhostty()
        }
    }

    private static func isClaudeCodeRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "claude"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func sendInterruptAndMessage() {
        let message = messages.randomElement() ?? "FASTER"
        let escaped = message.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let terminalApp = runningTerminalApp() ?? "Terminal"

        let script = """
        tell application "\(terminalApp)" to activate
        delay 0.1
        tell application "System Events"
            key code 8 using {control down}
            delay 0.05
            keystroke "\(escaped)"
            key code 36
        end tell
        """

        runAppleScript(script)
    }

    private static func launchClaudeInGhostty() {
        let ghosttyPath = "/Applications/Ghostty.app"
        let useGhostty = FileManager.default.fileExists(atPath: ghosttyPath)
        let appName = useGhostty ? "Ghostty" : "Terminal"

        let script = """
        tell application "\(appName)" to activate
        delay 0.5
        tell application "System Events"
            keystroke "claude"
            key code 36
        end tell
        """

        runAppleScript(script)
    }

    private static func runningTerminalApp() -> String? {
        let candidates = ["Ghostty", "iTerm2", "Terminal", "WarpTerminal", "Alacritty", "kitty"]
        for name in candidates {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = ["-x", name]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 { return name }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func runAppleScript(_ source: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            // Accessibility permissions may be required
        }
    }
}
