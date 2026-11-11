import CoreSpotlight

// Spotlight Add-ons once put entries of its own in Spotlight's list, Spotlight Add-ons Preferences
// and before it Clipboard History. It puts none there now: Spotlight Add-ons itself is in the list
// as any app is, and opening it opens the preferences. Any it put there before are taken out at
// each launch, which costs nothing where there are none.
enum Entry {
    static func removeAll() {
        CSSearchableIndex.default().deleteAllSearchableItems { error in
            if let error { Log.note("the old entries could not be taken out of Spotlight's list: \(error.localizedDescription)") }
        }
    }
}
