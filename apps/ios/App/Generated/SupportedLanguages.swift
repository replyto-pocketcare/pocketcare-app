import Foundation

// GENERATED FILE — do not hand-edit.
// Source: packages/core/i18n/src/index.ts (SUPPORTED_LANGUAGES)
// Regenerate with: node tools/parity/generate-i18n.mjs

/**
 One language the app ships strings for.

 `label` is the ENDONYM and is deliberately not translated: a picker that names
 languages in the language you are trying to leave is a picker you cannot use.
 */
public struct SupportedLanguage: Sendable, Identifiable, Equatable {
    public let code: String
    public let label: String
    public let rtl: Bool
    public var id: String { code }
}

/// Every language this build carries, source locale first.
public let supportedLanguages: [SupportedLanguage] = [
    SupportedLanguage(code: "en", label: "English", rtl: false),
    SupportedLanguage(code: "hi", label: "हिन्दी", rtl: false),
    SupportedLanguage(code: "nl", label: "Nederlands", rtl: false),
]
