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

import budgetsEn from "./locales/budgets/en.json";
import budgetsHi from "./locales/budgets/hi.json";
import budgetsNl from "./locales/budgets/nl.json";

import goalsEn from "./locales/goals/en.json";
import goalsHi from "./locales/goals/hi.json";
import goalsNl from "./locales/goals/nl.json";

import templatesEn from "./locales/templates/en.json";
import templatesHi from "./locales/templates/hi.json";
import templatesNl from "./locales/templates/nl.json";

import recurringEn from "./locales/recurring/en.json";
import recurringHi from "./locales/recurring/hi.json";
import recurringNl from "./locales/recurring/nl.json";

import cashflowEn from "./locales/cashflow/en.json";
import cashflowHi from "./locales/cashflow/hi.json";
import cashflowNl from "./locales/cashflow/nl.json";

import loansEn from "./locales/loans/en.json";
import loansHi from "./locales/loans/hi.json";
import loansNl from "./locales/loans/nl.json";

import investmentsEn from "./locales/investments/en.json";
import investmentsHi from "./locales/investments/hi.json";
import investmentsNl from "./locales/investments/nl.json";

import insightsEn from "./locales/insights/en.json";
import insightsHi from "./locales/insights/hi.json";
import insightsNl from "./locales/insights/nl.json";

import categoriesEn from "./locales/categories/en.json";
import categoriesHi from "./locales/categories/hi.json";
import categoriesNl from "./locales/categories/nl.json";

import labelsEn from "./locales/labels/en.json";
import labelsHi from "./locales/labels/hi.json";
import labelsNl from "./locales/labels/nl.json";

import searchEn from "./locales/search/en.json";
import searchHi from "./locales/search/hi.json";
import searchNl from "./locales/search/nl.json";

import dataEn from "./locales/data/en.json";
import dataHi from "./locales/data/hi.json";
import dataNl from "./locales/data/nl.json";

import groupsEn from "./locales/groups/en.json";
import groupsHi from "./locales/groups/hi.json";
import groupsNl from "./locales/groups/nl.json";

import joinEn from "./locales/join/en.json";
import joinHi from "./locales/join/hi.json";
import joinNl from "./locales/join/nl.json";

import helpEn from "./locales/help/en.json";
import helpHi from "./locales/help/hi.json";
import helpNl from "./locales/help/nl.json";

import loginEn from "./locales/login/en.json";
import loginHi from "./locales/login/hi.json";
import loginNl from "./locales/login/nl.json";

import settingsEn from "./locales/settings/en.json";
import settingsHi from "./locales/settings/hi.json";
import settingsNl from "./locales/settings/nl.json";

import statementsEn from "./locales/statements/en.json";
import statementsHi from "./locales/statements/hi.json";
import statementsNl from "./locales/statements/nl.json";

import statementsAnalyzeEn from "./locales/statementsAnalyze/en.json";
import statementsAnalyzeHi from "./locales/statementsAnalyze/hi.json";
import statementsAnalyzeNl from "./locales/statementsAnalyze/nl.json";

import onboardingEn from "./locales/onboarding/en.json";
import onboardingHi from "./locales/onboarding/hi.json";
import onboardingNl from "./locales/onboarding/nl.json";

import assistantEn from "./locales/assistant/en.json";
import assistantHi from "./locales/assistant/hi.json";
import assistantNl from "./locales/assistant/nl.json";

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
  en: { translation: en, splits: splitsEn, accounts: accountsEn, transactions: transactionsEn, cards: cardsEn, budgets: budgetsEn, goals: goalsEn, templates: templatesEn, recurring: recurringEn, cashflow: cashflowEn, loans: loansEn, investments: investmentsEn, insights: insightsEn, categories: categoriesEn, labels: labelsEn, search: searchEn, data: dataEn, groups: groupsEn, join: joinEn, help: helpEn, login: loginEn, settings: settingsEn, statements: statementsEn, statementsAnalyze: statementsAnalyzeEn, onboarding: onboardingEn, assistant: assistantEn },
  hi: { translation: hi, splits: splitsHi, accounts: accountsHi, transactions: transactionsHi, cards: cardsHi, budgets: budgetsHi, goals: goalsHi, templates: templatesHi, recurring: recurringHi, cashflow: cashflowHi, loans: loansHi, investments: investmentsHi, insights: insightsHi, categories: categoriesHi, labels: labelsHi, search: searchHi, data: dataHi, groups: groupsHi, join: joinHi, help: helpHi, login: loginHi, settings: settingsHi, statements: statementsHi, statementsAnalyze: statementsAnalyzeHi, onboarding: onboardingHi, assistant: assistantHi },
  nl: { translation: nl, splits: splitsNl, accounts: accountsNl, transactions: transactionsNl, cards: cardsNl, budgets: budgetsNl, goals: goalsNl, templates: templatesNl, recurring: recurringNl, cashflow: cashflowNl, loans: loansNl, investments: investmentsNl, insights: insightsNl, categories: categoriesNl, labels: labelsNl, search: searchNl, data: dataNl, groups: groupsNl, join: joinNl, help: helpNl, login: loginNl, settings: settingsNl, statements: statementsNl, statementsAnalyze: statementsAnalyzeNl, onboarding: onboardingNl, assistant: assistantNl },
} as const;

/** Registered namespaces. `translation` is the default; features add their own. */
export const NAMESPACES = ["translation", "splits", "accounts", "transactions", "cards", "budgets", "goals", "templates", "recurring", "cashflow", "loans", "investments", "insights", "categories", "labels", "search", "data", "groups", "join", "help", "login", "settings", "statements", "statementsAnalyze", "onboarding", "assistant"] as const;

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
