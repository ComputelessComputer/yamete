import AppKit
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

    enum Result {
        case whipped(String)
        case launched(String)
        case failed(String)

        var statusMessage: String {
            switch self {
            case let .whipped(message),
                 let .launched(message),
                 let .failed(message):
                return message
            }
        }
    }

    @discardableResult
    static func whip() -> Result {
        let message = messages.randomElement() ?? "FASTER"

        if let target = locateClaudeTarget() {
            if whip(target: target, message: message) {
                return .whipped("Whipped Claude in \(target.label).")
            }
            return .failed("Claude was detected, but Yamete could not inject into the active terminal session.")
        }

        if isClaudeCodeRunning() {
            if sendInterruptAndMessage(message: message) {
                return .whipped("Whipped Claude through a terminal focus fallback.")
            }
            return .failed("Claude is running, but Yamete could not find a scriptable terminal target.")
        } else {
            if launchClaudeInPreferredTerminal() {
                return .launched("Claude was not running, so Yamete opened a new terminal session.")
            }
            return .failed("Claude is not running and Yamete could not launch a supported terminal.")
        }
    }

    private enum ClaudeTarget {
        case terminal(windowIndex: Int, tabIndex: Int, tty: String)
        case ghostty(terminalID: String)

        var label: String {
            switch self {
            case .terminal:
                return "Terminal"
            case .ghostty:
                return "Ghostty"
            }
        }
    }

    private struct CommandResult {
        let terminationStatus: Int32
        let stdout: String
        let stderr: String
    }

    private static let terminalApps = ["Ghostty", "iTerm2", "Terminal", "Warp", "Alacritty", "kitty"]

    private static func locateClaudeTarget() -> ClaudeTarget? {
        if let target = locateTerminalTarget() {
            return target
        }

        if let target = locateGhosttyTarget() {
            return target
        }

        return nil
    }

    private static func locateTerminalTarget() -> ClaudeTarget? {
        let script = """
        tell application "Terminal"
            repeat with targetWindow in windows
                set windowIndex to index of targetWindow
                repeat with targetTab in tabs of targetWindow
                    set tabProcesses to processes of targetTab
                    if tabProcesses contains "claude" then
                        return (windowIndex as text) & "|" & ((index of targetTab) as text) & "|" & (tty of targetTab)
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """

        guard let output = runAppleScript(script)?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        let parts = output.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count == 3,
              let windowIndex = Int(parts[0]),
              let tabIndex = Int(parts[1]) else {
            return nil
        }

        return .terminal(windowIndex: windowIndex, tabIndex: tabIndex, tty: parts[2])
    }

    private static func locateGhosttyTarget() -> ClaudeTarget? {
        guard FileManager.default.fileExists(atPath: "/Applications/Ghostty.app") else {
            return nil
        }

        let script = """
        tell application "Ghostty"
            repeat with targetWindow in windows
                repeat with targetTab in tabs of targetWindow
                    if (name of targetTab) contains "claude" then
                        return id of (focused terminal of targetTab)
                    end if
                    repeat with targetTerminal in terminals of targetTab
                        if (name of targetTerminal) contains "claude" then
                            return id of targetTerminal
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """

        guard let output = runAppleScript(script)?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        return .ghostty(terminalID: output)
    }

    private static func whip(target: ClaudeTarget, message: String) -> Bool {
        switch target {
        case let .terminal(windowIndex, tabIndex, tty):
            if !interruptTTY(tty) {
                _ = sendFocusedControlC(to: "Terminal", windowIndex: windowIndex, tabIndex: tabIndex)
            }
            return sendTerminalMessage(message, windowIndex: windowIndex, tabIndex: tabIndex)

        case let .ghostty(terminalID):
            return sendGhosttyMessage(message, terminalID: terminalID)
        }
    }

    private static func interruptTTY(_ tty: String) -> Bool {
        let normalizedTTY = tty.replacingOccurrences(of: "/dev/", with: "")
        guard let result = runCommand(
            executable: "/usr/bin/pkill",
            arguments: ["-INT", "-t", normalizedTTY, "-f", "claude"],
            timeout: 1
        ) else {
            return false
        }

        return result.terminationStatus == 0
    }

    private static func sendTerminalMessage(_ message: String, windowIndex: Int, tabIndex: Int) -> Bool {
        let escaped = appleScriptEscaped(message)
        let script = """
        tell application "Terminal"
            set targetWindow to first window whose index is \(windowIndex)
            set targetTab to tab \(tabIndex) of targetWindow
            set selected tab of targetWindow to targetTab
            activate
            delay 0.05
            do script "\(escaped)" in targetTab
        end tell
        """

        guard let result = runAppleScript(script) else {
            return false
        }

        return result.terminationStatus == 0
    }

    private static func sendGhosttyMessage(_ message: String, terminalID: String) -> Bool {
        let escaped = appleScriptEscaped(message)
        let script = """
        tell application "Ghostty"
            set targetTerminal to first terminal whose id is "\(appleScriptEscaped(terminalID))"
            focus targetTerminal
            delay 0.05
            send key "c" modifiers "control" to targetTerminal
            delay 0.05
            input text "\(escaped)" to targetTerminal
            send key "enter" to targetTerminal
        end tell
        """

        guard let result = runAppleScript(script) else {
            return false
        }

        return result.terminationStatus == 0
    }

    private static func sendFocusedControlC(to terminalApp: String, windowIndex: Int? = nil, tabIndex: Int? = nil) -> Bool {
        let appSelectionScript: String
        if terminalApp == "Terminal", let windowIndex, let tabIndex {
            appSelectionScript = """
            tell application "Terminal"
                set targetWindow to first window whose index is \(windowIndex)
                set selected tab of targetWindow to tab \(tabIndex) of targetWindow
                activate
            end tell
            """
        } else {
            appSelectionScript = """
            tell application "\(terminalApp)" to activate
            """
        }

        let script = """
        \(appSelectionScript)
        delay 0.05
        tell application "System Events"
            key code 8 using {control down}
        end tell
        """

        guard let result = runAppleScript(script) else {
            return false
        }

        return result.terminationStatus == 0
    }

    private static func isClaudeCodeRunning() -> Bool {
        guard let result = runCommand(
            executable: "/usr/bin/pgrep",
            arguments: ["-f", "claude"],
            timeout: 1
        ) else {
            return false
        }

        return result.terminationStatus == 0
    }

    private static func sendInterruptAndMessage(message: String) -> Bool {
        let terminalApp = preferredTerminalApp() ?? "Terminal"
        let escaped = appleScriptEscaped(message)
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

        guard let result = runAppleScript(script) else {
            return false
        }

        return result.terminationStatus == 0
    }

    private static func launchClaudeInPreferredTerminal() -> Bool {
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

        guard let result = runAppleScript(script) else {
            return false
        }

        return result.terminationStatus == 0
    }

    private static func preferredTerminalApp() -> String? {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName,
           terminalApps.contains(frontmostApp) {
            return frontmostApp
        }

        return runningTerminalApp()
    }

    private static func runningTerminalApp() -> String? {
        for name in terminalApps {
            if let result = runCommand(
                executable: "/usr/bin/pgrep",
                arguments: ["-x", name],
                timeout: 1
            ), result.terminationStatus == 0 {
                return name
            }
        }
        return nil
    }

    private static func runAppleScript(_ source: String, timeout: TimeInterval = 2) -> CommandResult? {
        runCommand(executable: "/usr/bin/osascript", arguments: ["-e", source], timeout: timeout)
    }

    private static func runCommand(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> CommandResult? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
            if semaphore.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                _ = semaphore.wait(timeout: .now() + 1)
                return nil
            }

            let stdout = String(
                data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            return CommandResult(
                terminationStatus: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        } catch {
            return nil
        }
    }

    private static func appleScriptEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
