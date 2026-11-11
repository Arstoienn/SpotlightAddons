import AppKit
import UserNotifications

// When the app stops unexpectedly. The moment it does, a mark is left on disk and, if it had been
// running for more than half a minute, it is opened again (not after a crash on opening, which would
// only crash again). Opened after one, it says so in a notification, and the crash is written in
// SpotlightAddons.log whether or not the log is being kept: when, what stopped it, and, from the
// report macOS writes a few seconds later, where in the code it was and the report's own path.
enum Crash {
    private static let mark = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SpotlightAddons.crashed")
    private static let reports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
    private static let notifications = CrashNotifications()

    // Whether this launch is the one after a crash, which opens quietly, as at login.
    static var reopened: Bool { CommandLine.arguments.contains("--after-crash") }

    // Set up as the app starts. What the signal handler uses is made ready here, as it may do
    // nothing there but write a file and start a process.
    static func watch() {
        crashMark = strdup(mark.path)
        startedAt = time(nil)
        let again = "sleep 1; /usr/bin/open -g -a '\(Bundle.main.bundlePath)' --args --after-crash"
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 4)
        argv[0] = strdup("/bin/sh"); argv[1] = strdup("-c"); argv[2] = strdup(again); argv[3] = nil
        reopenArguments = argv
        environment = environ
        var action = sigaction()
        action.__sigaction_u.__sa_handler = crashed
        sigemptyset(&action.sa_mask)
        for signal in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] { sigaction(signal, &action, nil) }
        lookBack()
    }

    // A crash left marked by the last run: recorded, and said.
    private static func lookBack() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: mark.path),
              let when = attributes[.modificationDate] as? Date else { return }
        let signal = Int32((try? String(contentsOf: mark, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        try? FileManager.default.removeItem(at: mark)
        Log.always("Spotlight Add-ons stopped unexpectedly (\(name(signal)))" + (reopened ? " and was opened again." : "."))
        notify(reopened)
        // macOS's report is written some seconds after the crash; looked for when it should be there.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { attachReport(since: when) }
    }

    private static func name(_ signal: Int32) -> String {
        switch signal {
        case SIGSEGV: "SIGSEGV, a bad memory access"
        case SIGBUS: "SIGBUS, a bad memory access"
        case SIGILL, SIGTRAP: "\(signal == SIGILL ? "SIGILL" : "SIGTRAP"), a check in the code that failed"
        case SIGABRT: "SIGABRT, an abort"
        case SIGFPE: "SIGFPE, an arithmetic fault"
        default: "signal \(signal)"
        }
    }

    // The newest report macOS wrote for the app since the crash: its exception, the frames of the
    // thread that crashed, and where it is.
    private static func attachReport(since when: Date) {
        let found = (try? FileManager.default.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let report = found
            .filter { $0.lastPathComponent.hasPrefix("SpotlightAddons") && $0.pathExtension == "ips" }
            .compactMap { url in (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate).map { (url, $0) } }
            .filter { $0.1 >= when.addingTimeInterval(-10) }
            .max { $0.1 < $1.1 }?.0
        guard let report else { Log.always("No crash report from macOS was found in \(reports.path)."); return }
        var lines = ["Crash report: \(report.path)"]
        if let text = try? String(contentsOf: report, encoding: .utf8), let newline = text.firstIndex(of: "\n"),
           let body = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8)) as? [String: Any] {
            if let exception = body["exception"] as? [String: Any] {
                lines.append("  Exception: " + [exception["type"], exception["signal"], exception["subtype"]].compactMap { $0 as? String }.joined(separator: ", "))
            }
            let images = (body["usedImages"] as? [[String: Any]]) ?? []
            if let threads = body["threads"] as? [[String: Any]], let crashed = threads.first(where: { $0["triggered"] as? Bool == true }),
               let frames = crashed["frames"] as? [[String: Any]] {
                lines.append("  The thread that crashed:")
                for frame in frames.prefix(12) {
                    let image = (frame["imageIndex"] as? Int).flatMap { $0 < images.count ? images[$0]["name"] as? String : nil } ?? "?"
                    lines.append("    \(frame["symbol"] as? String ?? "?") (\(image))")
                }
            }
        }
        Log.always(lines.joined(separator: "\n"))
    }

    private static func notify(_ reopened: Bool) {
        let center = UNUserNotificationCenter.current()
        center.delegate = notifications
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Spotlight Add-ons quit unexpectedly"
            content.body = (reopened ? "It has been opened again. " : "") + "What happened is recorded in SpotlightAddons.log; click to open it."
            center.add(UNNotificationRequest(identifier: "crash", content: content, trigger: nil))
        }
    }
}

// The notification shown even though the app is the one in front, and a click on it opens the log.
final class CrashNotifications: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { NSWorkspace.shared.open(Log.url) }
        completionHandler()
    }
}

// What the signal handler reads: made ready beforehand, as it may not allocate.
nonisolated(unsafe) private var crashMark: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) private var reopenArguments: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
nonisolated(unsafe) private var environment: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
nonisolated(unsafe) private var startedAt: time_t = 0

// Only what is safe in a signal handler: the mark written with open and write, the app opened again
// with posix_spawn, and the signal then given its usual course, so that macOS still writes its report.
private func crashed(_ signal: Int32) {
    if let path = crashMark {
        let file = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if file >= 0 {
            var digits: (UInt8, UInt8, UInt8) = (UInt8(48 + signal / 10 % 10), UInt8(48 + signal % 10), 10)
            _ = withUnsafeBytes(of: &digits) { write(file, $0.baseAddress, 3) }
            close(file)
        }
    }
    if time(nil) - startedAt > 30, let argv = reopenArguments {
        var child: pid_t = 0
        _ = posix_spawn(&child, "/bin/sh", nil, nil, argv, environment)
    }
    Darwin.signal(signal, SIG_DFL)
    raise(signal)
}
