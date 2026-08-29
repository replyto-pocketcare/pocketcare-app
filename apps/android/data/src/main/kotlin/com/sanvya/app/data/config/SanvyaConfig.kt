package com.sanvya.app.data.config

import com.sanvya.app.data.BuildConfig

/**
 * Everything the app needs to know about *which* backend it is talking to.
 *
 * These five values were string literals in `DataModule.kt` — a build for a
 * different Supabase project meant editing source. They come from Gradle
 * properties now (`gradle.properties` for the committed defaults,
 * `local.properties` or `-P` to override), and this is the only type in the
 * codebase that reads `BuildConfig`.
 *
 * That indirection is the point. `BuildConfig` is generated per module, so a
 * `:app` class reading `com.sanvya.app.data.BuildConfig` would be reaching
 * across a module boundary into a generated symbol. Injecting this instead
 * means `:app` depends on an interface it can substitute in a test, and a
 * future flavour, remote-config lookup or per-environment switcher is a new
 * implementation rather than a rewrite of every call site.
 */
interface SanvyaConfig {
    val supabaseUrl: String
    val supabaseAnonKey: String
    val powerSyncUrl: String

    /**
     * Custom-scheme redirect the OAuth provider sends the browser back to.
     *
     * Web uses `${window.location.origin}/auth/callback`, an HTTP route. There
     * is no native equivalent and there must not be one: a native app cannot
     * host an HTTP endpoint, so the callback has to be a scheme the OS routes
     * back to this process. Supabase must have this exact URI in
     * Authentication → URL Configuration → Redirect URLs or the provider
     * refuses the round trip.
     */
    val authRedirectScheme: String
    val authRedirectHost: String

    /**
     * The SUPPORT public key (a JWK document), or null on a deployment that
     * has no support keypair.
     *
     * Web reads the same value from `NEXT_PUBLIC_SUPPORT_PUBLIC_JWK` and, when
     * it is absent, refuses a content grant with "Support access is not
     * configured for this deployment." Nullable rather than required for
     * exactly that reason: a build without it is a supported state, not a
     * misconfiguration, so this is the one key that must NOT hard-fail the way
     * the four above do.
     */
    val supportPublicJwk: String? get() = null

    /** The full redirect URI, assembled once so no caller concatenates it. */
    val authRedirectUri: String get() = "$authRedirectScheme://$authRedirectHost"
}

/** The shipping implementation: values baked in at build time. */
internal object BuildConfigSanvyaConfig : SanvyaConfig {
    override val supabaseUrl: String = BuildConfig.SUPABASE_URL
    override val supabaseAnonKey: String = BuildConfig.SUPABASE_ANON_KEY
    override val powerSyncUrl: String = BuildConfig.POWERSYNC_URL
    override val authRedirectScheme: String = BuildConfig.AUTH_REDIRECT_SCHEME
    override val authRedirectHost: String = BuildConfig.AUTH_REDIRECT_HOST
    override val supportPublicJwk: String? = BuildConfig.SUPPORT_PUBLIC_JWK.takeIf { it.isNotBlank() }
}

/** Factory, so `:app`'s DI wiring never names the implementation. */
fun sanvyaConfig(): SanvyaConfig = BuildConfigSanvyaConfig
