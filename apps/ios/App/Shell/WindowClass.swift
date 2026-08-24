import SwiftUI
import UIKit

/**
 What kind of device this is, as the platform itself reports it.

 `UIUserInterfaceIdiom` rather than a screen measurement: an iPad in a narrow
 Slide Over pane is iPad-sized hardware showing a phone-sized window, and the
 orientation policy is about the hardware.

 There is no shipping iOS foldable and no hinge API to ask about one. If that
 changes, `foldable` goes here beside the other two and gets the same
 all-orientations treatment Android's does — the policy already has a row for it
 (`docs/mobile/screen-specs/app-shell.md` §1b).
 */
enum SanvyaDeviceType {
    case phone
    case tablet
    /// CarPlay, Vision, Mac Catalyst, TV — none targeted; treated as tablet-ish.
    case other

    static var current: SanvyaDeviceType {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return .phone
        case .pad: return .tablet
        default: return .other
        }
    }

    /// Phones stay portrait; anything larger rotates freely (Akhilesh,
    /// 2026-08-23). Enforced declaratively in `Info.plist` via
    /// `UISupportedInterfaceOrientations` and its `~ipad` variant, so the system
    /// applies it before the first frame rather than after.
    var lockedToPortrait: Bool { self == .phone }
}

/**
 Which shell layout the current window is big enough for.

 The **size class does the real work**. It is the platform's own answer to "is
 this a phone-shaped window", it already accounts for Slide Over and Split View,
 and it changes when the window changes rather than when the device does. Only
 the split between the two regular-width layouts needs a measurement, and that
 uses the same generated constants Android reads, so the two apps agree about
 what a tablet is.

 See `docs/mobile/screen-specs/app-shell.md` §1.
 */
enum SanvyaWindowClass {
    /// Compact horizontal size class. Every iPhone, and any iPad window narrow
    /// enough that iOS itself calls it phone-shaped.
    case compact

    /// Regular, but not yet room for a sidebar. iPad portrait.
    case medium

    /// Regular and large. Sidebar, inset window frame, no bottom bar.
    case expanded

    /// Web hides the bar's text labels on its smallest tier; so do we.
    var showsNavLabels: Bool { self != .compact }

    /// Whether the floating bottom bar is the navigation at this size.
    var usesBottomBar: Bool { self != .expanded }

    /// Whether the content column is capped and centred rather than full-bleed.
    var capsContentWidth: Bool { self != .compact }
}

func sanvyaWindowClass(
    horizontalSizeClass: UserInterfaceSizeClass?,
    size: CGSize
) -> SanvyaWindowClass {
    guard horizontalSizeClass == .regular else { return .compact }
    // The same generated constants Android reads, so the two apps switch at
    // the same place. Height matters as much as width: the sidebar is a
    // full-height column, and a short wide window has the width for one and
    // nowhere to put it.
    if size.width >= SanvyaMetrics.WindowClass.expandedWidth
        && size.height >= SanvyaMetrics.WindowClass.mediumHeight {
        return .expanded
    }
    return .medium
}

private struct WindowClassKey: EnvironmentKey {
    static let defaultValue: SanvyaWindowClass = .compact
}

extension EnvironmentValues {
    var sanvyaWindowClass: SanvyaWindowClass {
        get { self[WindowClassKey.self] }
        set { self[WindowClassKey.self] = newValue }
    }
}

/**
 Measures the window and publishes `\.sanvyaWindowClass` to everything beneath.

 A `GeometryReader` rather than a cached value read once at launch: on iPad,
 Stage Manager, Split View and Slide Over all change the window's width at
 runtime **with no rotation event**, so anything that caches a size class across
 a layout pass is wrong the moment someone drags a divider.

 A class change is a **resize, not a relaunch**. Scroll position, the selected
 tab, an open sheet and in-progress form input all survive it.
 */
struct WindowClassReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            content()
                // GeometryReader parks its content at topLeading and does not
                // stretch it. Without this the whole app would sit in the
                // corner at its intrinsic size.
                .frame(width: proxy.size.width, height: proxy.size.height)
                .environment(
                    \.sanvyaWindowClass,
                    sanvyaWindowClass(
                        horizontalSizeClass: horizontalSizeClass,
                        size: proxy.size
                    )
                )
        }
    }
}
