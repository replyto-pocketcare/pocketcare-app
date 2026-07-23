/**
 * i18next-parser — scans source for `t('key')` / `useTranslation('ns')` and
 * keeps the locale catalogs in sync. Run: `pnpm i18n:extract`.
 *
 * Layout is namespace-first to match the app: one JSON per (namespace, locale)
 * at packages/core/i18n/src/locales/<namespace>/<locale>.json. Existing
 * translations are preserved; newly-found keys are added blank for authoring,
 * and removed keys are kept (not deleted) so an in-progress rollout never drops
 * strings. Review the diff, fill in `en`, then translate `hi` / `nl`.
 */
export default {
  locales: ["en", "hi", "nl"],

  // Where components live.
  input: [
    "apps/web/app/**/*.{ts,tsx}",
    "apps/web/src/**/*.{ts,tsx}",
  ],

  // One catalog per (namespace, locale).
  output: "packages/core/i18n/src/locales/$NAMESPACE/$LOCALE.json",

  defaultNamespace: "translation",
  keySeparator: ".",
  namespaceSeparator: ":",

  // Safe defaults for an incremental rollout.
  keepRemoved: true,        // don't delete keys that are temporarily unreferenced
  createOldCatalogs: false, // no *_old.json backups
  sort: true,
  indentation: 2,
  lineEnding: "lf",

  // Blank value for new keys so untranslated strings are obvious in review.
  defaultValue: "",

  // TS + JSX aware.
  lexers: {
    ts: ["JavascriptLexer"],
    tsx: ["JsxLexer"],
    js: ["JavascriptLexer"],
    jsx: ["JsxLexer"],
  },

  verbose: true,
};
