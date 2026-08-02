import SwiftUI

public enum Theme {
    // Dynamic Colors based on colorScheme environment, but hardcoded as Color(uiColor: ...) 
    // or we can use custom SwiftUI Colors. To keep it simple, we provide standard colors
    // and rely on Color(UIColor { trait in ... }) for light/dark mode support.
}

extension Color {
    public static let bg = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 32/255.0, green: 29/255.0, blue: 25/255.0, alpha: 1) : UIColor(red: 239/255.0, green: 233/255.0, blue: 223/255.0, alpha: 1) })
    public static let surface = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 42/255.0, green: 37/255.0, blue: 33/255.0, alpha: 1) : UIColor(red: 255/255.0, green: 253/255.0, blue: 249/255.0, alpha: 1) })
    public static let surface2 = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 51/255.0, green: 45/255.0, blue: 39/255.0, alpha: 1) : UIColor(red: 243/255.0, green: 235/255.0, blue: 221/255.0, alpha: 1) })
    public static let border = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 60/255.0, green: 53/255.0, blue: 45/255.0, alpha: 1) : UIColor(red: 231/255.0, green: 220/255.0, blue: 205/255.0, alpha: 1) })
    public static let borderStrong = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 70/255.0, green: 61/255.0, blue: 51/255.0, alpha: 1) : UIColor(red: 228/255.0, green: 216/255.0, blue: 199/255.0, alpha: 1) })
    
    public static let text = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 241/255.0, green: 232/255.0, blue: 222/255.0, alpha: 1) : UIColor(red: 43/255.0, green: 39/255.0, blue: 35/255.0, alpha: 1) })
    public static let text2 = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 168/255.0, green: 155/255.0, blue: 138/255.0, alpha: 1) : UIColor(red: 138/255.0, green: 125/255.0, blue: 108/255.0, alpha: 1) })
    public static let text3 = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 168/255.0, green: 155/255.0, blue: 138/255.0, alpha: 1) : UIColor(red: 167/255.0, green: 154/255.0, blue: 136/255.0, alpha: 1) })
    
    public static let accent = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 201/255.0, green: 138/255.0, blue: 114/255.0, alpha: 1) : UIColor(red: 176/255.0, green: 106/255.0, blue: 79/255.0, alpha: 1) })
    public static let accentSoft = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 176/255.0, green: 106/255.0, blue: 79/255.0, alpha: 1) : UIColor(red: 201/255.0, green: 138/255.0, blue: 114/255.0, alpha: 1) })
    
    public static let positive = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 156/255.0, green: 174/255.0, blue: 142/255.0, alpha: 1) : UIColor(red: 95/255.0, green: 122/255.0, blue: 82/255.0, alpha: 1) })
    public static let negative = Color(UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(red: 207/255.0, green: 138/255.0, blue: 116/255.0, alpha: 1) : UIColor(red: 168/255.0, green: 80/255.0, blue: 58/255.0, alpha: 1) })
}
