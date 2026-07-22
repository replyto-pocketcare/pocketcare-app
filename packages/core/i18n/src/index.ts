/**
 * @pocketcare/i18n — shared internationalization layer for mobile + web.
 * i18next handles translation + ICU pluralization; number/date/currency
 * formatting is delegated to the platform `Intl` APIs (see @pocketcare/money).
 */
import i18n from "i18next";
import { initReactI18next } from "react-i18next";

// Layout: locales/<namespace>/<lng>.json. `translation` is the shared/default
// namespace; each feature owns its own JSON per language so files stay small,
// reviewable, independently loadable, and i18next-parser can extract keys into
// one consistent output pattern (see i18next-parser.config.mjs).
import en from "./locales/translation/en.json";
import hi from "./locales/translation/hi.json";
import nl from "./locales/translation/nl.json";

import splitsEn from "./locales/splits/en.json";
import splitsHi from "./locales/splits/hi.json";
import splitsNl from "./locales/splits/nl.json";

import accountsEn from "./locales/accounts/en.json";
import accountsHi from "./locales/accounts/hi.json";
import accountsNl from "./locales/accounts/nl.json";

import transactionsEn from "./locales/transactions/en.json";
import transactionsHi from "./locales/transactions/hi.json";
import transactionsNl from "./locales/transactions/nl.json";

import cardsEn from "./locales/cards/en.json";
import cardsHi from "./locales/cards/hi.json";
import cardsNl from "./locales/cards/nl.json";

export interface Language {
  code: string;
  label: string;
  /** Text direction; drives RTL layout. */
  dir: "ltr" | "rtl";
}

export const SUPPORTED_LANGUAGES: readonly Language[] = [
  { code: "en", label: "English", dir: "ltr" },
  { code: "hi", label: "हिन्दी", dir: "ltr" },
  { code: "nl", label: "Nederlands", dir: "ltr" },
];

export const resources = {
  en: { translation: en, splits: splitsEn, accounts: accountsEn, transactions: transactionsEn, cards: cardsEn },
  hi: { translation: hi, splits: splitsHi, accounts: accountsHi, transactions: transactionsHi, cards: cardsHi },
  nl: { translation: nl, splits: splitsNl, accounts: accountsNl, transactions: transactionsNl, cards: cardsNl },
} as const;

/** Registered namespaces. `translation` is the default; features add their own. */
export const NAMESPACES = ["translation", "splits", "accounts", "transactions", "cards"] as const;

export function isRtl(languageCode: string): boolean {
  const base = languageCode.split("-")[0];
  return SUPPORTED_LANGUAGES.some((l) => l.code === base && l.dir === "rtl");
}

/**
 * Initialize the shared i18n instance.
 * @param lng resolved device/user language (e.g. from expo-localization or navigator.language)
 */
export function initI18n(lng = "en") {
  if (!i18n.isInitialized) {
    void i18n.use(initReactI18next).init({
      resources,
      lng,
      fallbackLng: "en",
      supportedLngs: SUPPORTED_LANGUAGES.map((l) => l.code),
      ns: NAMESPACES,
      defaultNS: "translation",
      interpolation: { escapeValue: false },
      returnNull: false,
    });
  }
  return i18n;
}

export default i18n;
