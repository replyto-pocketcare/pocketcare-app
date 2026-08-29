import Foundation

/// Everything the app needs to know about *which* backend it is talking to.
///
/// These values were string literals in `DataModule.swift` — a build for a
/// different Supabase project meant editing source. They come from
/// `Config/Sanvya.xcconfig` now, via Info.plist, and this is the only type in
/// the codebase that reads Info.plist for them.
///
/// A protocol rather than a struct of constants for the same reason Android
/// has an interface here: a test, a future staging scheme, or a remote-config
/// lookup becomes a second conformance rather than an edit to every call site.
public protocol SanvyaConfig: Sendable {
    var supabaseURL: URL { get }
    var supabaseAnonKey: String { get }
    var powerSyncURL: String { get }

    /// Custom-scheme callback the OAuth provider returns to.
    ///
    /// Web redirects to `${window.location.origin}/auth/callback`, an HTTP
    /// route. There is no native equivalent and there must not be one — a
    /// native app cannot host an HTTP endpoint, so the callback has to be a
    /// scheme the OS routes back into this process. Supabase must list this
    /// exact URI under Authentication → URL Configuration → Redirect URLs.
    var authRedirectScheme: String { get }
    var authRedirectHost: String { get }

    /// The SUPPORT public key (a JWK document), or nil on a deployment that
    /// has no support keypair.
    ///
    /// Web reads the same value from `NEXT_PUBLIC_SUPPORT_PUBLIC_JWK` and,
    /// when it is absent, refuses a content grant with "Support access is not
    /// configured for this deployment." Optional rather than required for
    /// exactly that reason: a build without it is a supported state, not a
    /// misconfiguration, so this is the one key that must NOT trap at launch
    /// the way the five above do.
    var supportPublicJwk: String? { get }
}

public extension SanvyaConfig {
    /// Absent unless a conformance says otherwise.
    var supportPublicJwk: String? { nil }

    /// The full redirect URI, assembled once so no caller concatenates it.
    var authRedirectURL: URL {
        // Force-unwrap is safe and deliberate: the components come from build
        // settings validated at launch by `BundleSanvyaConfig.init`, so if this
        // could fail the app has already trapped with a better message.
        URL(string: "\(authRedirectScheme)://\(authRedirectHost)")!
    }
}

/// The shipping implementation: values injected into Info.plist at build time.
public struct BundleSanvyaConfig: SanvyaConfig {
    public let supabaseURL: URL
    public let supabaseAnonKey: String
    public let powerSyncURL: String
    public let authRedirectScheme: String
    public let authRedirectHost: String
    public let supportPublicJwk: String?

    public init(bundle: Bundle = .main) {
        // Hosts, not URLs. xcconfig treats `//` as a comment start anywhere on
        // a line, so a full `https://…` value silently truncates to `https:`.
        // The scheme is prepended here, where a slash is just a slash — see
        // Config/Sanvya.xcconfig's header.
        let supabaseHost = Self.require(bundle, "SanvyaSupabaseHost")
        let powerSyncHost = Self.require(bundle, "SanvyaPowerSyncHost")

        guard let url = URL(string: "https://\(supabaseHost)") else {
            fatalError("SanvyaSupabaseHost is not a usable host: \(supabaseHost)")
        }
        self.supabaseURL = url
        self.powerSyncURL = "https://\(powerSyncHost)"
        self.supabaseAnonKey = Self.require(bundle, "SanvyaSupabaseAnonKey")
        self.authRedirectScheme = Self.require(bundle, "SanvyaAuthRedirectScheme")
        self.authRedirectHost = Self.require(bundle, "SanvyaAuthRedirectHost")
        self.supportPublicJwk = Self.optional(bundle, "SanvyaSupportPublicJwk")
    }

    /// `require`'s counterpart for a key whose absence is a supported state.
    ///
    /// Same three rejections -- missing, empty, and an unresolved `$(...)`
    /// build setting reaching Info.plist verbatim -- but they yield nil rather
    /// than a crash, because a build with no support keypair is a build that
    /// simply cannot issue content grants, which is exactly where web is
    /// without its env var.
    private static func optional(_ bundle: Bundle, _ key: String) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else {
            return nil
        }
        return value
    }

    /// Missing configuration traps at launch rather than defaulting to "".
    ///
    /// An app that starts up pointed at nothing fails later, somewhere else,
    /// as a network error — which is a far more expensive thing to track down
    /// than a crash on line one naming the key that is missing.
    private static func require(_ bundle: Bundle, _ key: String) -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              // An unresolved build setting reaches Info.plist verbatim.
              !value.hasPrefix("$(") else {
            fatalError("""
                Missing Info.plist key '\(key)'.
                It comes from Config/Sanvya.xcconfig — check that the target's \
                configFiles still point at it and re-run `xcodegen generate`.
                """)
        }
        return value
    }
}
