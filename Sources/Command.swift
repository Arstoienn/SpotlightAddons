import Foundation

// A line for Terminal, typed after >: > top, >ls -la. The card shows the line as it was typed, and
// clicking it, or Return with the pointer moved onto it, types the line at the prompt in a new
// Terminal window. It is never run here: it runs when Return is pressed in Terminal, which is for
// the person to decide. Off unless chosen in the settings.
//
// The line is handed to Terminal as a parameter of an Apple Event to a fixed, compiled script, and
// not written into the script's source; nothing is run in this process, which may read Spotlight
// and watch the keyboard.
struct Command {
    var line: String       // after the >, exactly as typed but for the spaces before it
    var typeable: Bool     // the shell is zsh, which can be given a line to wait at its prompt; no other can

    static func parse(_ typed: String) -> Command? {
        guard Options.commands else { return nil }
        // One line: no newline, carriage return or other control character; a tab may be in it.
        guard !typed.unicodeScalars.contains(where: { $0 != "\t" && CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix(">") else { return nil }
        let line = String(text.dropFirst().drop(while: { $0 == " " || $0 == "\t" }))
        guard !line.isEmpty else { return nil }
        return Command(line: line, typeable: shellIsZsh)
    }

    // zsh can be given a line to wait at its next prompt, unrun (print -z); other shells cannot.
    static let shellIsZsh: Bool = {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return true }
        return String(cString: shell).hasSuffix("/zsh")
    }()

    // What the card says under the line: Return anywhere, where that is chosen (as it is at
    // first), or only with the pointer on the card.
    var solution: Solution {
        guard typeable else { return Solution(exact: line, approx: "Not typed: the shell is not zsh, which can be given a line to wait at its prompt") }
        return Solution(exact: line, approx: Options.commandReturn ? "Press Return, or click, to type it in Terminal without running it"
                                                                   : "Click, or press Return here, to type it in Terminal without running it")
    }

    // What Terminal is given: zsh's print -z, which puts the line at the next prompt for Return to
    // run, the line inside single quotes, in which nothing is special but the quote itself, written
    // '\''. The screen is cleared first, so that the line waits alone. (Control characters, which
    // could end the string another way, never reach here: parse refuses them.)
    var script: String? {
        typeable ? " clear; print -rz -- '" + line.replacingOccurrences(of: "'", with: "'\\''") + "'" : nil
    }

    // What went wrong in handing a line over, for the log; set by the app, which keeps the log.
    nonisolated(unsafe) static var report: (String) -> Void = { _ in }

    // The script, compiled once. Its one handler takes what Terminal is to be given as a parameter,
    // and gives it to Terminal in a new window. Where Terminal was not running, opening it opens a
    // window of its own, and that one is used rather than a second beside it.
    nonisolated(unsafe) private static var compiled: NSAppleScript? = {
        let source = """
        on runcommand(typedLine)
            set wasRunning to application "Terminal" is running
            tell application "Terminal"
                activate
                if wasRunning then
                    do script typedLine
                else
                    repeat 50 times
                        if (count of windows) > 0 then exit repeat
                        delay 0.1
                    end repeat
                    if (count of windows) > 0 then
                        do script typedLine in window 1
                    else
                        do script typedLine
                    end if
                end if
            end tell
        end runcommand
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else {
            report("the Terminal script did not compile: \(error ?? [:])")
            return nil
        }
        return script
    }()

    // When the last line was handed to Terminal: a click or Return made while it was on its way,
    // as when macOS was asking whether Terminal may be controlled, waits behind it, and would open
    // a second window as soon as the first had gone.
    nonisolated(unsafe) private static var lastGiven = Date.distantPast
    nonisolated(unsafe) private static var giving = false

    // Types the line in a new Terminal window. Later on the main queue, and not at once: Return is
    // read inside the keyboard's event tap, and the first time macOS asks whether Terminal may be
    // controlled, which would hold the tap up while it waits.
    // True where the line is on its way; false where it is not given at all, as for one asked for
    // again while the last is still on its way.
    @discardableResult func type() -> Bool {
        guard let given = script, !Command.giving, Date().timeIntervalSince(Command.lastGiven) > 1.5 else { return false }
        Command.giving = true
        let count = line.count
        DispatchQueue.main.async {
            defer { Command.giving = false; Command.lastGiven = Date() }
            guard let compiled = Command.compiled else { return }
            // 'ascr'/'psbr': call a subroutine of the script by name ('snam'), its parameters
            // the direct object ('----'), a list.
            let event = NSAppleEventDescriptor(eventClass: 0x6173_6372, eventID: 0x7073_6272, targetDescriptor: .currentProcess(),
                                               returnID: -1, transactionID: 0)
            event.setParam(NSAppleEventDescriptor(string: "runcommand"), forKeyword: 0x736E_616D)
            let parameters = NSAppleEventDescriptor.list()
            parameters.insert(NSAppleEventDescriptor(string: given), at: 1)
            event.setParam(parameters, forKeyword: 0x2D2D_2D2D)
            var error: NSDictionary?
            compiled.executeAppleEvent(event, error: &error)
            if let error {
                // -1743: not allowed to control Terminal, under Privacy & Security › Automation.
                Command.report("a command was not given to Terminal: \(error[NSAppleScript.errorNumber] ?? "?") \(error[NSAppleScript.errorMessage] ?? "")")
            } else {
                Command.report("a command was typed in Terminal (\(count) characters)")
            }
        }
        return true
    }
}
