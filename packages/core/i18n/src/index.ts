/**
 * @pocketcare/i18n — shared internationalization layer for mobile + web.
 * i18next handles translation + ICU pluralization; number/date/currency
 * formatting is delegated to the platform `Intl` APIs (see @pocketcare/money).
 */
import i18n from "i18next";
import { initReactI18next } from "react-i18next";

import en from "./locales/en.json";
import hi from "./locales/hi.json";
import ar from "./locales/ar.json";

export interface Language {
  code: string;
  label: string;
  /** Text direction; drives RTL layout. */
  dir: "ltr" | "rtl";
}

export const SUPPORTED_LANGUAGES: readonly Language[] = [
  { code: "en", label: "English", dir: "ltr" },
  { code: "hi", label: "हिन्दी", dir: "ltr" },
  { code: "ar", label: "العربية", dir: "rtl" },
];

export const resources = {
  en: { translation: en },
  hi: { translation: hi },
  ar: { translation: ar },
} as const;

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
      interpolation: { escapeValue: false },
      returnNull: false,
    });
  }
  return i18n;
}

export default i18n;
