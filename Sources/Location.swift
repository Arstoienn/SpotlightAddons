import Foundation

// A path to a file or folder, typed in whole: /Users/shane/Code/App/build/app.jar. Spotlight's own
// search does little with an absolute path, so the card names what is there, and shows it in
// Finder when the card is clicked, or Return is pressed with the pointer on it.
struct Location {
    var url: URL
    var isFolder: Bool

    // What is typed as an absolute path that exists. One from the home folder, ~/Code, Spotlight
    // already finds, and is left to it. Dragged from Finder or a terminal it may be in quotes, with
    // backslashes before its spaces, or as file://.
    static func parse(_ typed: String) -> Location? {
        guard Options.paths else { return nil }
        var s = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2, let q = s.first, q == "'" || q == "\"", s.last == q { s = String(s.dropFirst().dropLast()) }
        if s.hasPrefix("file://"), let path = URL(string: s)?.path { s = path }
        s = s.replacingOccurrences(of: "\\ ", with: " ")
        guard s.hasPrefix("/"), s.count > 1, !s.contains("\n") else { return nil }
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        var folder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: s, isDirectory: &folder) else { return nil }
        return Location(url: URL(fileURLWithPath: s), isFolder: folder.boolValue && !isPackage(s))
    }

    // An app or a bundle is a folder on disk and one thing to a person: it is shown, not opened.
    private static func isPackage(_ path: String) -> Bool {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
    }

    // Its name, and where it is, from the home folder where it is in it.
    var solution: Solution {
        let home = NSHomeDirectory()
        func short(_ path: String) -> String { path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path }
        let name = url.lastPathComponent
        return isFolder ? Solution(exact: name, approx: "A folder, opened in Finder: \(short(url.path))")
                        : Solution(exact: name, approx: "In \(short(url.deletingLastPathComponent().path)), shown in Finder")
    }
}
