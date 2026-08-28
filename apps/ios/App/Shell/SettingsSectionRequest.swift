import Foundation
import SwiftUI

/// The sections of the Settings page that something else can link INTO.
enum SettingsSection: String {
    /// Web's `/settings#problems` — the dead-letter queue panel.
    case problems
}

/**
 The `#fragment` half of a deep link into Settings.

 Web's sync-problems banner pushes `/settings#problems` and the browser scrolls
 the panel into view. A tab has no fragment, so the intent has to travel beside
 the tab change: the banner records the section here, `SettingsView` scrolls to
 it once the panel is actually on screen, and clears it.

 One-shot on purpose — a request that stayed set would silently jump the page on
 the next, unrelated visit to Settings. `SettingsView` also clears it on the way
 out, so a request that could not be honoured (the failed writes cleared before
 the screen appeared) dies with the screen.

 Shaped as an `ObservableObject` singleton rather than `@Observable`, mirroring
 `Prefs.shared`: it is app-wide state a view observes, and the two should not be
 wired two different ways on the same screen.
 */
@MainActor
final class SettingsSectionRequest: ObservableObject {
    static let shared = SettingsSectionRequest()

    @Published var pending: SettingsSection?

    private init() {}

    func request(_ section: SettingsSection) { pending = section }

    func consume() { pending = nil }
}
