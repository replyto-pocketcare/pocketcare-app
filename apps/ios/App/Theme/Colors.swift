import SwiftUI

// GENERATED FILE — do not hand-edit.
// Source: apps/web/app/globals.css + tools/parity/tokens.spec.mjs
// Regenerate with: node tools/parity/generate-tokens.mjs

public extension Color {
    static let bg = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.1255, green: 0.1137, blue: 0.0980, alpha: 1)
            : UIColor(red: 0.9373, green: 0.9137, blue: 0.8745, alpha: 1)
    })
    static let surface = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.1647, green: 0.1451, blue: 0.1294, alpha: 1)
            : UIColor(red: 1.0000, green: 0.9922, blue: 0.9765, alpha: 1)
    })
    static let surface2 = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.2000, green: 0.1765, blue: 0.1529, alpha: 1)
            : UIColor(red: 0.9529, green: 0.9216, blue: 0.8667, alpha: 1)
    })
    static let border = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.2353, green: 0.2078, blue: 0.1765, alpha: 1)
            : UIColor(red: 0.9059, green: 0.8627, blue: 0.8039, alpha: 1)
    })
    static let borderStrong = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.2745, green: 0.2392, blue: 0.2000, alpha: 1)
            : UIColor(red: 0.8941, green: 0.8471, blue: 0.7804, alpha: 1)
    })
    static let sidebar = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.1490, green: 0.1294, blue: 0.1059, alpha: 1)
            : UIColor(red: 0.9647, green: 0.9412, blue: 0.9059, alpha: 1)
    })
    static let text = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.9451, green: 0.9098, blue: 0.8706, alpha: 1)
            : UIColor(red: 0.1686, green: 0.1529, blue: 0.1373, alpha: 1)
    })
    static let text2 = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.6588, green: 0.6078, blue: 0.5412, alpha: 1)
            : UIColor(red: 0.5412, green: 0.4902, blue: 0.4235, alpha: 1)
    })
    static let text3 = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.6549, green: 0.6039, blue: 0.5333, alpha: 1)
            : UIColor(red: 0.6549, green: 0.6039, blue: 0.5333, alpha: 1)
    })
    static let accent = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.7882, green: 0.5412, blue: 0.4471, alpha: 1)
            : UIColor(red: 0.6902, green: 0.4157, blue: 0.3098, alpha: 1)
    })
    static let accentHover = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.5608, green: 0.3255, blue: 0.2353, alpha: 1)
            : UIColor(red: 0.5608, green: 0.3255, blue: 0.2353, alpha: 1)
    })
    static let accentSoft = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.6902, green: 0.4157, blue: 0.3098, alpha: 1)
            : UIColor(red: 0.7882, green: 0.5412, blue: 0.4471, alpha: 1)
    })
    static let accentGhost = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.2275, green: 0.1804, blue: 0.1529, alpha: 1)
            : UIColor(red: 0.9412, green: 0.8471, blue: 0.7882, alpha: 1)
    })
    static let positive = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.6118, green: 0.6824, blue: 0.5569, alpha: 1)
            : UIColor(red: 0.3725, green: 0.4784, blue: 0.3216, alpha: 1)
    })
    static let negative = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.8118, green: 0.5412, blue: 0.4549, alpha: 1)
            : UIColor(red: 0.6588, green: 0.3137, blue: 0.2275, alpha: 1)
    })
    static let warning = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.8157, green: 0.6431, blue: 0.3608, alpha: 1)
            : UIColor(red: 0.7529, green: 0.5412, blue: 0.2431, alpha: 1)
    })
    static let teal = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.1843, green: 0.4353, blue: 0.4157, alpha: 1)
            : UIColor(red: 0.1843, green: 0.4353, blue: 0.4157, alpha: 1)
    })
    static let sage = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.6118, green: 0.6824, blue: 0.5569, alpha: 1)
            : UIColor(red: 0.6118, green: 0.6824, blue: 0.5569, alpha: 1)
    })
    static let forest = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.7961, green: 0.8392, blue: 0.7412, alpha: 1)
            : UIColor(red: 0.2431, green: 0.2902, blue: 0.2196, alpha: 1)
    })

    // Unambiguous twins for the tokens SwiftUI also declares on `Color`.
    // Prefer these at call sites -- see SWIFTUI_COLOR_STATICS in the generator.
    static let sanvyaTeal = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.1843, green: 0.4353, blue: 0.4157, alpha: 1)
            : UIColor(red: 0.1843, green: 0.4353, blue: 0.4157, alpha: 1)
    })
}
