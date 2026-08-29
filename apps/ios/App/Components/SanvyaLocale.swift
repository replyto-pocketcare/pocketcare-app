import Foundation
import Observation
import os

/**
 The app's chosen language, and the bundle every generated string reads from.

 ## Why this exists at all

 `String(localized:table:)` resolves against `Bundle.main.preferredLocalizations`
 — the SYSTEM language, full stop. There is no seam in it. So for most of this
 port, `settings.language` was a key in the catalogue with nothing behind it: any
 picker a Settings screen offered would have changed a stored value and left
 every one of the ~1,600 accessors reading the system language regardless.

 That is why the fix is in the GENERATOR rather than in a screen. Every accessor
 in `S.swift` now passes `bundle: SanvyaLocale.bundle`, so overriding the bundle
 overrides the whole catalogue at once, and no call site has to know.

 ## How the override works

 Xcode compiles `Localizable.xcstrings` into one `.lproj` directory per language
 inside the app bundle. Pointing `Bundle(path:)` at `hi.lproj` gives a bundle
 whose only strings are the Hindi ones, and `String(localized:bundle:)` reads it
 directly. No `swizzle`, no private API, and nothing to keep in sync with the
 catalogue: a language added to the xcstrings gains an `.lproj` automatically.

 `nil` means "follow the system", which is the default and the only state an
 install starts in.

 ## Why the bundle is cached

 Every string in the app goes through this property, including inside tight list
 rows. `Bundle(path:)` hits the filesystem, so resolving it per string would put
 a stat on the render path of every label. The cache is invalidated only when the
 code changes, which happens once per user decision.

 ## Making the UI notice

 SwiftUI has no reason to re-render when a global changes, so `LocalePrefs` is
 `@Observable` and the root view is keyed on `code`. Changing the language
 rebuilds the tree, which is the honest thing to do: strings are read eagerly all
 over the app and there is no way to re-evaluate them in place.
 */
public enum SanvyaLocale {
    /// The override and its resolved bundle, behind one lock.
    ///
    /// `nonisolated(unsafe) static var` would have been shorter and this file
    /// nearly shipped with it. It is the wrong call here: this is read by EVERY
    /// string in the app, from any thread, and written from the main actor while
    /// those reads are in flight. "Probably fine on ARM64" is not a thing to put
    /// under 1,700 accessors.
    ///
    /// `OSAllocatedUnfairLock` rather than `NSLock` because this is genuinely on
    /// the hot path -- an unfair lock is a handful of nanoseconds uncontended,
    /// and it is `Sendable`, so the whole enum stays usable from anywhere with
    /// no isolation annotation. iOS 16+; the deployment target is 17.
    ///
    /// `uncheckedState` / `withLockUnchecked` rather than the checked forms:
    /// those are constrained `where State: Sendable`, and `State` holds a
    /// `Bundle?`, whose `Sendable` audit varies by SDK. The safety argument is
    /// the lock itself, not the constraint, so nothing is given up -- and the
    /// checked form would fail to compile on some SDKs and not others, which is
    /// the worst kind of dependency to take.
    private static let state = OSAllocatedUnfairLock(
        uncheckedState: State(code: LocalePrefs.readStoredCode(), cached: nil)
    )

    private struct State {
        var code: String?
        /// Resolved lazily and kept. Every string in the app goes through this,
        /// including inside tight list rows, and `Bundle(path:)` hits the
        /// filesystem -- resolving per string would put a stat on the render
        /// path of every label. Invalidated only when the code changes, which
        /// is once per user decision.
        var cached: Bundle?
    }

    /// The language override, or nil to follow the system.
    public static var code: String? {
        state.withLockUnchecked { $0.code }
    }

    /// The bundle every generated accessor reads from.
    public static var bundle: Bundle {
        state.withLockUnchecked { s in
            if let cached = s.cached { return cached }
            let resolved = resolve(s.code)
            s.cached = resolved
            return resolved
        }
    }

    /// The `Locale` every generated accessor formats with.
    ///
    /// Separate from `bundle` and equally necessary. `String(localized:)`
    /// defaults `locale:` to `.current` -- the SYSTEM locale -- so without this
    /// the STRINGS would come from the override while PLURAL CATEGORY SELECTION
    /// still followed the phone. Harmless for en/hi/nl, which share one/other
    /// rules; a real bug the day somebody adds Arabic, Polish or Russian, and a
    /// bug that would only show up on a specific count.
    public static var locale: Locale {
        state.withLockUnchecked { s in
            s.code.map(Locale.init(identifier:)) ?? .current
        }
    }

    /// Change the language. Call through `LocalePrefs.select` so the UI updates.
    static func apply(_ newCode: String?) {
        state.withLockUnchecked { s in
            s.code = newCode
            s.cached = nil
        }
    }

    private static func resolve(_ code: String?) -> Bundle {
        guard let code else { return .main }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            // Falling back to `.main` is deliberate for a language the bundle
            // does not carry: the system language beats raw keys.
            //
            // But it is LOUD in debug, because this is the one way the whole
            // feature dies silently. If `hi.lproj` is not in the built product
            // -- a `knownRegions` or `CFBundleLocalizations` problem, not a code
            // one -- the picker stores a choice, rebuilds the entire tree, and
            // renders exactly the same English. No error, no log, nothing to
            // notice. `LocalePrefs.available` exists to make that state visible
            // in the picker too.
            assertionFailure("No .lproj for '\(code)' in the app bundle. Check knownRegions / CFBundleLocalizations.")
            return .main
        }
        return bundle
    }
}

/// The language choice, as something SwiftUI can watch.
///
/// The list is not hardcoded here: it is read from what the app bundle actually
/// ships, so adding a locale to `packages/core/i18n` and regenerating is the
/// only step. A hand-written list would silently offer a language with no
/// strings behind it.
@Observable
@MainActor
public final class LocalePrefs {
    public static let shared = LocalePrefs()

    /// nil = follow the system.
    public private(set) var code: String? = LocalePrefs.readStoredCode()

    private init() {}

    public func select(_ newCode: String?) {
        guard newCode != code else { return }
        code = newCode
        SanvyaLocale.apply(newCode)
        if let newCode {
            UserDefaults.standard.set(newCode, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    /// The languages this build actually carries strings for, source first.
    public var available: [String] {
        let source = Bundle.main.developmentLocalization
        let rest = Bundle.main.localizations
            .filter { $0 != source && $0 != "Base" }
            .sorted()
        return ([source].compactMap { $0 }) + rest
    }

    nonisolated static func readStoredCode() -> String? {
        UserDefaults.standard.string(forKey: storageKey)
    }
}

/// Web stores the same choice under `i18nextLng`; this is the native key for it.
/// Deliberately NOT that name -- the two clients do not share storage, and a
/// name that implies they do would invite someone to try.
private let storageKey = "pc_language"
