import Foundation

// GENERATED FILE — do not hand-edit.
// Source: packages/core/i18n/src/locales/**
// Regenerate with: node tools/parity/generate-i18n.mjs

/**
 Typed access to every translated string, grouped by the same namespace web
 uses. `S.Transactions.item(n: "2")` is the native equivalent of web's
 `useTranslation("transactions")` + `t("item", { n: 2 })`, and unlike a bare
 `String(localized:)` it stops compiling the moment a key is renamed or an
 interpolation argument is added.

 Non-plural arguments are typed `String`, not `CVarArg`, and the call site
 stringifies. They are emitted as `%@`, which `String(format:)` reads as an
 OBJECT POINTER: an `Int` passed there prints a garbage address instead of a
 number, silently, at runtime. Twelve call sites were doing exactly that before
 the parameter type was tightened — "3 minutes ago" among them.
 */
public enum S {
    public enum Accounts {
        public static var accountName: String { String(localized: "accounts:accountName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var acrossCurrencies: String { String(localized: "accounts:acrossCurrencies", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allowNeg: String { String(localized: "accounts:allowNeg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allowNegOff: String { String(localized: "accounts:allowNegOff", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allowNegOn: String { String(localized: "accounts:allowNegOn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func amountDue(currency: String) -> String {
            String(format: String(localized: "accounts:amountDue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), currency)
        }
        public static func approx(amount: String) -> String {
            String(format: String(localized: "accounts:approx", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var archivedTag: String { String(localized: "accounts:archivedTag", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var balAlready: String { String(localized: "accounts:balAlready", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var balanceHeading: String { String(localized: "accounts:balanceHeading", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func balUpdated(amount: String) -> String {
            String(format: String(localized: "accounts:balUpdated", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var cancel: String { String(localized: "accounts:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var changeDirectly: String { String(localized: "accounts:changeDirectly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var colour: String { String(localized: "accounts:colour", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func convertedNote(base: String) -> String {
            String(format: String(localized: "accounts:convertedNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), base)
        }
        public static var creditCardDetails: String { String(localized: "accounts:creditCardDetails", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func creditLimit(currency: String) -> String {
            String(format: String(localized: "accounts:creditLimit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), currency)
        }
        public static var currency: String { String(localized: "accounts:currency", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var currentBalance: String { String(localized: "accounts:currentBalance", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var delete: String { String(localized: "accounts:delete", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteAll: String { String(localized: "accounts:deleteAll", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteBody: String { String(localized: "accounts:deleteBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteKeep: String { String(localized: "accounts:deleteKeep", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteTitle: String { String(localized: "accounts:deleteTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dematNote: String { String(localized: "accounts:dematNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var directNote: String { String(localized: "accounts:directNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dueDay: String { String(localized: "accounts:dueDay", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func dueNextCycle(amount: String, date: String) -> String {
            String(format: String(localized: "accounts:dueNextCycle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount, date)
        }
        public static func dueThisCycle(amount: String, date: String) -> String {
            String(format: String(localized: "accounts:dueThisCycle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount, date)
        }
        public static var edit: String { String(localized: "accounts:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var editTitle: String { String(localized: "accounts:editTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var hideArchived: String { String(localized: "accounts:hideArchived", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var includeNw: String { String(localized: "accounts:includeNw", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var includeShort: String { String(localized: "accounts:includeShort", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var inNetWorth: String { String(localized: "accounts:inNetWorth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func invested(currency: String) -> String {
            String(format: String(localized: "accounts:invested", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), currency)
        }
        public static var loading: String { String(localized: "accounts:loading", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newAccount: String { String(localized: "accounts:newAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newBalance: String { String(localized: "accounts:newBalance", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newTitle: String { String(localized: "accounts:newTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noAccounts: String { String(localized: "accounts:noAccounts", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noBankLink: String { String(localized: "accounts:noBankLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func openingBalance(currency: String) -> String {
            String(format: String(localized: "accounts:openingBalance", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), currency)
        }
        public static var recordAsTxn: String { String(localized: "accounts:recordAsTxn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "accounts:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var saveChanges: String { String(localized: "accounts:saveChanges", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var saving: String { String(localized: "accounts:saving", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func showArchived(count: String) -> String {
            String(format: String(localized: "accounts:showArchived", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var statementDay: String { String(localized: "accounts:statementDay", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "accounts:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func totalCurrencies(total: String, count: String) -> String {
            String(format: String(localized: "accounts:totalCurrencies", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), total, count)
        }
        public static var txnNote: String { String(localized: "accounts:txnNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeCash: String { String(localized: "accounts:type.cash", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeCreditCard: String { String(localized: "accounts:type.credit_card", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeCurrent: String { String(localized: "accounts:type.current", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeDemat: String { String(localized: "accounts:type.demat", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeMutualFunds: String { String(localized: "accounts:type.mutual_funds", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeSavings: String { String(localized: "accounts:type.savings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeStocks: String { String(localized: "accounts:type.stocks", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeLabel: String { String(localized: "accounts:typeLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unarchive: String { String(localized: "accounts:unarchive", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var updateBalance: String { String(localized: "accounts:updateBalance", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Assistant {
        public static var chats: String { String(localized: "assistant:chats", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var composerPlaceholder: String { String(localized: "assistant:composerPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirm: String { String(localized: "assistant:confirm", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirmAction: String { String(localized: "assistant:confirmAction", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var continueConversation: String { String(localized: "assistant:continueConversation", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func creditsSuffix(n: String) -> String {
            String(format: String(localized: "assistant:creditsSuffix", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), n)
        }
        public static var deleteChatAria: String { String(localized: "assistant:deleteChatAria", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteChatMsg: String { String(localized: "assistant:deleteChatMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteChatTitle: String { String(localized: "assistant:deleteChatTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errDefault: String { String(localized: "assistant:errDefault", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func errGeneric(err: String) -> String {
            String(format: String(localized: "assistant:errGeneric", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), err)
        }
        public static var errModel: String { String(localized: "assistant:errModel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errNetwork: String { String(localized: "assistant:errNetwork", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errNotConfigured: String { String(localized: "assistant:errNotConfigured", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var goPremium: String { String(localized: "assistant:goPremium", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var greeting: String { String(localized: "assistant:greeting", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var help: String { String(localized: "assistant:help", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var landingIntro: String { String(localized: "assistant:landingIntro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var micDenied: String { String(localized: "assistant:micDenied", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var micHint: String { String(localized: "assistant:micHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var micSpeak: String { String(localized: "assistant:micSpeak", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var micStop: String { String(localized: "assistant:micStop", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var micTranscribing: String { String(localized: "assistant:micTranscribing", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newChat: String { String(localized: "assistant:newChat", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noChats: String { String(localized: "assistant:noChats", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var opening: String { String(localized: "assistant:opening", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var outFreeBold: String { String(localized: "assistant:outFreeBold", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var outFreeRest: String { String(localized: "assistant:outFreeRest", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var outPaidBold: String { String(localized: "assistant:outPaidBold", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var outPaidRest: String { String(localized: "assistant:outPaidRest", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func paymentFailed(msg: String) -> String {
            String(format: String(localized: "assistant:paymentFailed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), msg)
        }
        public static var premiumBody: String { String(localized: "assistant:premiumBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var premiumFeature: String { String(localized: "assistant:premiumFeature", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var privacyBody: String { String(localized: "assistant:privacyBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var privacyTitle: String { String(localized: "assistant:privacyTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var queries: String { String(localized: "assistant:queries", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func quotaResets(date: String) -> String {
            String(format: String(localized: "assistant:quotaResets", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), date)
        }
        public static var seePlans: String { String(localized: "assistant:seePlans", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sendAria: String { String(localized: "assistant:sendAria", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var skip: String { String(localized: "assistant:skip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var startChat: String { String(localized: "assistant:startChat", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestions: [String] {
            [
                String(localized: "assistant:suggestions.1", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale),
                String(localized: "assistant:suggestions.2", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale),
                String(localized: "assistant:suggestions.3", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale),
                String(localized: "assistant:suggestions.4", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale),
                String(localized: "assistant:suggestions.5", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale),
                String(localized: "assistant:suggestions.6", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale),
                String(localized: "assistant:suggestions.7", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale),
            ]
        }
        public static var thinking: String { String(localized: "assistant:thinking", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "assistant:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var understand: String { String(localized: "assistant:understand", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var untitledChat: String { String(localized: "assistant:untitledChat", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var viewData: String { String(localized: "assistant:viewData", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Budgets {
        public static var addBudget: String { String(localized: "budgets:addBudget", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addCategories: String { String(localized: "budgets:addCategories", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var alertAt: String { String(localized: "budgets:alertAt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var alertMeAt: String { String(localized: "budgets:alertMeAt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allSpending: String { String(localized: "budgets:allSpending", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var breakdownEmpty: String { String(localized: "budgets:breakdownEmpty", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var breakdownFallback: String { String(localized: "budgets:breakdownFallback", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var breakdownLoading: String { String(localized: "budgets:breakdownLoading", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func breakdownMismatch(amount: String) -> String {
            String(format: String(localized: "budgets:breakdownMismatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static func breakdownSummary(count: Int, amount: String) -> String {
            String(format: String(localized: "budgets:breakdownSummary", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count, amount)
        }
        public static func breakdownTitleAria(title: String) -> String {
            String(format: String(localized: "budgets:breakdownTitleAria", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), title)
        }
        public static var breakdownTotal: String { String(localized: "budgets:breakdownTotal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "budgets:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var categoriesEmpty: String { String(localized: "budgets:categoriesEmpty", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var categoriesOptional: String { String(localized: "budgets:categoriesOptional", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var createFirst: String { String(localized: "budgets:createFirst", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var customDates: String { String(localized: "budgets:customDates", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteBudgetAria: String { String(localized: "budgets:deleteBudgetAria", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func deleteMsg(title: String) -> String {
            String(format: String(localized: "budgets:deleteMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), title)
        }
        public static var deleteTitle: String { String(localized: "budgets:deleteTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var edit: String { String(localized: "budgets:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errDates: String { String(localized: "budgets:errDates", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errLimit: String { String(localized: "budgets:errLimit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var labels: String { String(localized: "budgets:labels", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var labelsOptional: String { String(localized: "budgets:labelsOptional", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func left(amount: String) -> String {
            String(format: String(localized: "budgets:left", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static func limit(currency: String) -> String {
            String(format: String(localized: "budgets:limit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), currency)
        }
        public static var limitShort: String { String(localized: "budgets:limitShort", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var nameOptional: String { String(localized: "budgets:nameOptional", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var namePlaceholder: String { String(localized: "budgets:namePlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newBudget: String { String(localized: "budgets:newBudget", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noBudgetsBody: String { String(localized: "budgets:noBudgetsBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noBudgetsTitle: String { String(localized: "budgets:noBudgetsTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func over(amount: String) -> String {
            String(format: String(localized: "budgets:over", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var percentOfLimit: String { String(localized: "budgets:percentOfLimit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var periodDaily: String { String(localized: "budgets:period.daily", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var periodMonthly: String { String(localized: "budgets:period.monthly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var periodWeekly: String { String(localized: "budgets:period.weekly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var periodYearly: String { String(localized: "budgets:period.yearly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recurring: String { String(localized: "budgets:recurring", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "budgets:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var spendChartAria: String { String(localized: "budgets:spendChartAria", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func spendChartLimit(amount: String) -> String {
            String(format: String(localized: "budgets:spendChartLimit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static func spent(amount: String) -> String {
            String(format: String(localized: "budgets:spent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var timeframe: String { String(localized: "budgets:timeframe", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "budgets:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var viewSpentAria: String { String(localized: "budgets:viewSpentAria", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Cards {
        public static var addCard: String { String(localized: "cards:addCard", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var amountDue: String { String(localized: "cards:amountDue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var amountPlaceholder: String { String(localized: "cards:amountPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func availableCredit(amount: String) -> String {
            String(format: String(localized: "cards:availableCredit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var cancel: String { String(localized: "cards:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cardHolder: String { String(localized: "cards:cardHolder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cardNumber: String { String(localized: "cards:cardNumber", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cardNumberPlaceholder: String { String(localized: "cards:cardNumberPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cardTxnsTitle: String { String(localized: "cards:cardTxnsTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func cardTxnsTotal(amount: String) -> String {
            String(format: String(localized: "cards:cardTxnsTotal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var clickToManage: String { String(localized: "cards:clickToManage", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var creditLimit: String { String(localized: "cards:creditLimit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dueDay: String { String(localized: "cards:dueDay", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func dueNextCycle(amount: String) -> String {
            String(format: String(localized: "cards:dueNextCycle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var dueThisCycle: String { String(localized: "cards:dueThisCycle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var editDetails: String { String(localized: "cards:editDetails", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func emiCoveredBody(count: Int) -> String {
            String(format: String(localized: "cards:emiCoveredBody", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var emiCoveredConfirm: String { String(localized: "cards:emiCoveredConfirm", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emiCoveredSkip: String { String(localized: "cards:emiCoveredSkip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emiCoveredTitle: String { String(localized: "cards:emiCoveredTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func emiNo(n: String) -> String {
            String(format: String(localized: "cards:emiNo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), n)
        }
        public static var emptyBody: String { String(localized: "cards:emptyBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newAccount: String { String(localized: "cards:newAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func newSpendThisCycle(amount: String) -> String {
            String(format: String(localized: "cards:newSpendThisCycle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var noCardTxns: String { String(localized: "cards:noCardTxns", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func ofLimit(limit: String) -> String {
            String(format: String(localized: "cards:ofLimit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), limit)
        }
        public static var payBy: String { String(localized: "cards:payBy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "cards:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settle: String { String(localized: "cards:settle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settleFrom: String { String(localized: "cards:settleFrom", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var spentThisCycle: String { String(localized: "cards:spentThisCycle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func statement(date: String) -> String {
            String(format: String(localized: "cards:statement", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), date)
        }
        public static var statementDay: String { String(localized: "cards:statementDay", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var subtitle: String { String(localized: "cards:subtitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "cards:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var uncategorised: String { String(localized: "cards:uncategorised", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var viewTransactions: String { String(localized: "cards:viewTransactions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wallet: String { String(localized: "cards:wallet", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Cashflow {
        public static func actions(name: String) -> String {
            String(format: String(localized: "cashflow:actions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var add: String { String(localized: "cashflow:add", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addIncome: String { String(localized: "cashflow:addIncome", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addIncomeTitle: String { String(localized: "cashflow:addIncomeTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addPayment: String { String(localized: "cashflow:addPayment", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addPaymentTitle: String { String(localized: "cashflow:addPaymentTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addRecurringSaving: String { String(localized: "cashflow:addRecurringSaving", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addSavingsTitle: String { String(localized: "cashflow:addSavingsTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var amount: String { String(localized: "cashflow:amount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func amountCur(base: String) -> String {
            String(format: String(localized: "cashflow:amountCur", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), base)
        }
        public static var autoPosts: String { String(localized: "cashflow:autoPosts", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "cashflow:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var categoryOptional: String { String(localized: "cashflow:categoryOptional", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func commitments(count: String) -> String {
            String(format: String(localized: "cashflow:commitments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var confirm: String { String(localized: "cashflow:confirm", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var depositInto: String { String(localized: "cashflow:depositInto", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dirLabelIncome: String { String(localized: "cashflow:dirLabel.income", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dirLabelPayment: String { String(localized: "cashflow:dirLabel.payment", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var edit: String { String(localized: "cashflow:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emiPerMonth: String { String(localized: "cashflow:emiPerMonth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyIncomes: String { String(localized: "cashflow:emptyIncomes", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyPayments: String { String(localized: "cashflow:emptyPayments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptySavings: String { String(localized: "cashflow:emptySavings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var financialSummary: String { String(localized: "cashflow:financialSummary", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var firstDue: String { String(localized: "cashflow:firstDue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var freeSurplus: String { String(localized: "cashflow:freeSurplus", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var freqDaily: String { String(localized: "cashflow:freq.daily", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var freqMonthly: String { String(localized: "cashflow:freq.monthly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var freqWeekly: String { String(localized: "cashflow:freq.weekly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var freqYearly: String { String(localized: "cashflow:freq.yearly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var frequency: String { String(localized: "cashflow:frequency", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var goToLoans: String { String(localized: "cashflow:goToLoans", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var incomeMinusPayments: String { String(localized: "cashflow:incomeMinusPayments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var incomeVsPayments: String { String(localized: "cashflow:incomeVsPayments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var intoSavings: String { String(localized: "cashflow:intoSavings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var intro: String { String(localized: "cashflow:intro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var loanFallback: String { String(localized: "cashflow:loanFallback", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var loanNote: String { String(localized: "cashflow:loanNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func loanSubtitle(amount: String) -> String {
            String(format: String(localized: "cashflow:loanSubtitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var makeRecurring: String { String(localized: "cashflow:makeRecurring", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func modalAdd(what: String) -> String {
            String(format: String(localized: "cashflow:modalAdd", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), what)
        }
        public static func modalEdit(what: String) -> String {
            String(format: String(localized: "cashflow:modalEdit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), what)
        }
        public static var name: String { String(localized: "cashflow:name", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var netDifference: String { String(localized: "cashflow:netDifference", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var netMonthly: String { String(localized: "cashflow:netMonthly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func next(date: String) -> String {
            String(format: String(localized: "cashflow:next", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), date)
        }
        public static var nextDue: String { String(localized: "cashflow:nextDue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var nextExpected: String { String(localized: "cashflow:nextExpected", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noCategory: String { String(localized: "cashflow:noCategory", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var oneOff: String { String(localized: "cashflow:oneOff", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payFrom: String { String(localized: "cashflow:payFrom", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payments: String { String(localized: "cashflow:payments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func per(unit: String) -> String {
            String(format: String(localized: "cashflow:per", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), unit)
        }
        public static func perAnnum(pct: String) -> String {
            String(format: String(localized: "cashflow:perAnnum", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), pct)
        }
        public static var perMonth: String { String(localized: "cashflow:perMonth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var plannedPayments: String { String(localized: "cashflow:plannedPayments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var plannedPaymentsTitle: String { String(localized: "cashflow:plannedPaymentsTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func plans(count: String) -> String {
            String(format: String(localized: "cashflow:plans", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func portfolioMeta(count: Int, amount: String) -> String {
            String(format: String(localized: "cashflow:portfolioMeta", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count, amount)
        }
        public static var portfolioTitle: String { String(localized: "cashflow:portfolioTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var postAuto: String { String(localized: "cashflow:postAuto", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var postAutoOff: String { String(localized: "cashflow:postAutoOff", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var projNote: String { String(localized: "cashflow:projNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var quickAdd: String { String(localized: "cashflow:quickAdd", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var quickAddNoteLink: String { String(localized: "cashflow:quickAddNoteLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var quickAddNotePost: String { String(localized: "cashflow:quickAddNotePost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var quickAddNotePre: String { String(localized: "cashflow:quickAddNotePre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recurringIncome: String { String(localized: "cashflow:recurringIncome", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recurringIncomes: String { String(localized: "cashflow:recurringIncomes", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var remove: String { String(localized: "cashflow:remove", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func removeItemMsg(name: String) -> String {
            String(format: String(localized: "cashflow:removeItemMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var removeItemTitle: String { String(localized: "cashflow:removeItemTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func removeLoanMsg(name: String) -> String {
            String(format: String(localized: "cashflow:removeLoanMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var removeLoanTitle: String { String(localized: "cashflow:removeLoanTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func removeRecurringMsg(name: String) -> String {
            String(format: String(localized: "cashflow:removeRecurringMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var removeRecurringTitle: String { String(localized: "cashflow:removeRecurringTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func removeSubMsg(name: String) -> String {
            String(format: String(localized: "cashflow:removeSubMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var removeSubTitle: String { String(localized: "cashflow:removeSubTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var returnPa: String { String(localized: "cashflow:returnPa", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var returnPct: String { String(localized: "cashflow:returnPct", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "cashflow:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var savingEllipsis: String { String(localized: "cashflow:savingEllipsis", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var savingsInvest: String { String(localized: "cashflow:savingsInvest", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var selectAccount: String { String(localized: "cashflow:selectAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func spentSoFar(amount: String, date: String) -> String {
            String(format: String(localized: "cashflow:spentSoFar", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount, date)
        }
        public static func spentTooltip(count: String, date: String) -> String {
            String(format: String(localized: "cashflow:spentTooltip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count, date)
        }
        public static var startedRenewal: String { String(localized: "cashflow:startedRenewal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var subscription: String { String(localized: "cashflow:subscription", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var timeframeNounDaily: String { String(localized: "cashflow:timeframeNoun.daily", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var timeframeNounMonthly: String { String(localized: "cashflow:timeframeNoun.monthly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var timeframeNounWeekly: String { String(localized: "cashflow:timeframeNoun.weekly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var timeframeNounYearly: String { String(localized: "cashflow:timeframeNoun.yearly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "cashflow:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trackHoldingsLink: String { String(localized: "cashflow:trackHoldingsLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trackHoldingsPost: String { String(localized: "cashflow:trackHoldingsPost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trackHoldingsPre: String { String(localized: "cashflow:trackHoldingsPre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var viewSchedule: String { String(localized: "cashflow:viewSchedule", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var whereIncomeGoes: String { String(localized: "cashflow:whereIncomeGoes", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Categories {
        public static var add: String { String(localized: "categories:add", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var backToSettings: String { String(localized: "categories:backToSettings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "categories:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var collapse: String { String(localized: "categories:collapse", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "categories:deleteMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var deleteTitle: String { String(localized: "categories:deleteTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var edit: String { String(localized: "categories:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var expand: String { String(localized: "categories:expand", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var expense: String { String(localized: "categories:expense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var income: String { String(localized: "categories:income", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindExpense: String { String(localized: "categories:kind.expense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindIncome: String { String(localized: "categories:kind.income", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var name: String { String(localized: "categories:name", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newCategory: String { String(localized: "categories:newCategory", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "categories:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var searchPlaceholder: String { String(localized: "categories:searchPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "categories:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var topLevel: String { String(localized: "categories:topLevel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func under(name: String) -> String {
            String(format: String(localized: "categories:under", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
    }

    public enum Dashboard {
        public static var accountsAdd: String { String(localized: "dashboard:accountsAdd", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var accountsAddA11y: String { String(localized: "dashboard:accountsAddA11y", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addWidget: String { String(localized: "dashboard:addWidget", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addWidgetIntro: String { String(localized: "dashboard:addWidgetIntro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allAdded: String { String(localized: "dashboard:allAdded", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askCollapseA11y: String { String(localized: "dashboard:askCollapseA11y", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askExpandA11y: String { String(localized: "dashboard:askExpandA11y", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askPlaceholder: String { String(localized: "dashboard:askPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askQuickBudgetLabel: String { String(localized: "dashboard:askQuick.budgetLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askQuickBudgetPrompt: String { String(localized: "dashboard:askQuick.budgetPrompt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askQuickFindLabel: String { String(localized: "dashboard:askQuick.findLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askQuickFindPrompt: String { String(localized: "dashboard:askQuick.findPrompt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askQuickGoalLabel: String { String(localized: "dashboard:askQuick.goalLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askQuickGoalPrompt: String { String(localized: "dashboard:askQuick.goalPrompt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askQuickWhereLabel: String { String(localized: "dashboard:askQuick.whereLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askQuickWherePrompt: String { String(localized: "dashboard:askQuick.wherePrompt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var askSendA11y: String { String(localized: "dashboard:askSendA11y", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var customize: String { String(localized: "dashboard:customize", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var efShort: String { String(localized: "dashboard:efShort", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyBody: String { String(localized: "dashboard:emptyBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyBudgets: String { String(localized: "dashboard:emptyBudgets", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyCashflow: String { String(localized: "dashboard:emptyCashflow", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyGoals: String { String(localized: "dashboard:emptyGoals", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyLabels: String { String(localized: "dashboard:emptyLabels", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyRecent: String { String(localized: "dashboard:emptyRecent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptySpending: String { String(localized: "dashboard:emptySpending", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptySplits: String { String(localized: "dashboard:emptySplits", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptySubscriptions: String { String(localized: "dashboard:emptySubscriptions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyTitle: String { String(localized: "dashboard:emptyTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyUpcoming: String { String(localized: "dashboard:emptyUpcoming", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var greetingAfternoon: String { String(localized: "dashboard:greetingAfternoon", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var greetingEvening: String { String(localized: "dashboard:greetingEvening", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var greetingFallback: String { String(localized: "dashboard:greetingFallback", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var greetingMorning: String { String(localized: "dashboard:greetingMorning", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var greetingNight: String { String(localized: "dashboard:greetingNight", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var hideAmountsA11y: String { String(localized: "dashboard:hideAmountsA11y", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var inflow: String { String(localized: "dashboard:inflow", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var lastMonth: String { String(localized: "dashboard:lastMonth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func moreCategories(count: String) -> String {
            String(format: String(localized: "dashboard:moreCategories", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func moreItems(count: String) -> String {
            String(format: String(localized: "dashboard:moreItems", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var moveDown: String { String(localized: "dashboard:moveDown", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var moveUp: String { String(localized: "dashboard:moveUp", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var net: String { String(localized: "dashboard:net", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var outflow: String { String(localized: "dashboard:outflow", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var perMonth: String { String(localized: "dashboard:perMonth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var premium: String { String(localized: "dashboard:premium", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var premiumNote: String { String(localized: "dashboard:premiumNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var showAmountsA11y: String { String(localized: "dashboard:showAmountsA11y", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func singleCurrency(base: String) -> String {
            String(format: String(localized: "dashboard:singleCurrency", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), base)
        }
        public static func spent(amount: String) -> String {
            String(format: String(localized: "dashboard:spent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var statHidden: String { String(localized: "dashboard:statHidden", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var statIncome: String { String(localized: "dashboard:statIncome", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var statNetWorth: String { String(localized: "dashboard:statNetWorth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var statSaved: String { String(localized: "dashboard:statSaved", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var statSpending: String { String(localized: "dashboard:statSpending", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func statVsLastMonth(amount: String) -> String {
            String(format: String(localized: "dashboard:statVsLastMonth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static func subsCount(count: Int) -> String {
            String(format: String(localized: "dashboard:subsCount", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func subsCountSpent(count: Int, amount: String) -> String {
            String(format: String(localized: "dashboard:subsCountSpent", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count, amount)
        }
        public static var subsSpentNote: String { String(localized: "dashboard:subsSpentNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestBudgetsBody: String { String(localized: "dashboard:suggest.budgets.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestBudgetsCta: String { String(localized: "dashboard:suggest.budgets.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestBudgetsTitle: String { String(localized: "dashboard:suggest.budgets.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestCreditCardsBody: String { String(localized: "dashboard:suggest.creditCards.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestCreditCardsCta: String { String(localized: "dashboard:suggest.creditCards.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestCreditCardsTitle: String { String(localized: "dashboard:suggest.creditCards.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestGoalsBody: String { String(localized: "dashboard:suggest.goals.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestGoalsCta: String { String(localized: "dashboard:suggest.goals.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestGoalsTitle: String { String(localized: "dashboard:suggest.goals.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestInvestmentsBody: String { String(localized: "dashboard:suggest.investments.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestInvestmentsCta: String { String(localized: "dashboard:suggest.investments.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestInvestmentsTitle: String { String(localized: "dashboard:suggest.investments.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestLoansBody: String { String(localized: "dashboard:suggest.loans.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestLoansCta: String { String(localized: "dashboard:suggest.loans.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestLoansTitle: String { String(localized: "dashboard:suggest.loans.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestReceiptsBody: String { String(localized: "dashboard:suggest.receipts.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestReceiptsCta: String { String(localized: "dashboard:suggest.receipts.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestReceiptsTitle: String { String(localized: "dashboard:suggest.receipts.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestRecurringBody: String { String(localized: "dashboard:suggest.recurring.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestRecurringCta: String { String(localized: "dashboard:suggest.recurring.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestRecurringTitle: String { String(localized: "dashboard:suggest.recurring.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestSplitsBody: String { String(localized: "dashboard:suggest.splits.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestSplitsCta: String { String(localized: "dashboard:suggest.splits.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestSplitsTitle: String { String(localized: "dashboard:suggest.splits.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestSubscriptionsBody: String { String(localized: "dashboard:suggest.subscriptions.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestSubscriptionsCta: String { String(localized: "dashboard:suggest.subscriptions.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestSubscriptionsTitle: String { String(localized: "dashboard:suggest.subscriptions.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func suggestDismiss(title: String) -> String {
            String(format: String(localized: "dashboard:suggestDismiss", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), title)
        }
        public static var suggestSubtitle: String { String(localized: "dashboard:suggestSubtitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestTitle: String { String(localized: "dashboard:suggestTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thisMonth: String { String(localized: "dashboard:thisMonth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileBudgets: String { String(localized: "dashboard:tile.budgets", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileByCategory: String { String(localized: "dashboard:tile.byCategory", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileByLabel: String { String(localized: "dashboard:tile.byLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileCashflow: String { String(localized: "dashboard:tile.cashflow", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileCurrencies: String { String(localized: "dashboard:tile.currencies", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileGoals: String { String(localized: "dashboard:tile.goals", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileMonthCompare: String { String(localized: "dashboard:tile.monthCompare", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileNetTrend: String { String(localized: "dashboard:tile.netTrend", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileRecent: String { String(localized: "dashboard:tile.recent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileSpending: String { String(localized: "dashboard:tile.spending", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileSplits: String { String(localized: "dashboard:tile.splits", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileSubscriptions: String { String(localized: "dashboard:tile.subscriptions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileTrends: String { String(localized: "dashboard:tile.trends", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tileUpcoming: String { String(localized: "dashboard:tile.upcoming", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trendLast1m: String { String(localized: "dashboard:trendLast1m", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trendLast1w: String { String(localized: "dashboard:trendLast1w", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trendLast1y: String { String(localized: "dashboard:trendLast1y", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trendLast3d: String { String(localized: "dashboard:trendLast3d", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trialBannerBody: String { String(localized: "dashboard:trialBannerBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func trialBannerTitle(days: String) -> String {
            String(format: String(localized: "dashboard:trialBannerTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), days)
        }
        public static func trialDays(count: Int) -> String {
            String(format: String(localized: "dashboard:trialDays", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var trialLater: String { String(localized: "dashboard:trialLater", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trialLoseAssistant: String { String(localized: "dashboard:trialLoseAssistant", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trialLoseAutomation: String { String(localized: "dashboard:trialLoseAutomation", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trialLoseCsv: String { String(localized: "dashboard:trialLoseCsv", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trialLoseInsights: String { String(localized: "dashboard:trialLoseInsights", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trialSeePlans: String { String(localized: "dashboard:trialSeePlans", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trialUpgrade: String { String(localized: "dashboard:trialUpgrade", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func trialWelcomeFooter(days: String) -> String {
            String(format: String(localized: "dashboard:trialWelcomeFooter", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), days)
        }
        public static var trialWelcomeIntro: String { String(localized: "dashboard:trialWelcomeIntro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func trialWelcomeSubtitle(days: String) -> String {
            String(format: String(localized: "dashboard:trialWelcomeSubtitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), days)
        }
        public static var trialWelcomeTitle: String { String(localized: "dashboard:trialWelcomeTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var viewAll: String { String(localized: "dashboard:viewAll", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func viewAllCount(n: String) -> String {
            String(format: String(localized: "dashboard:viewAllCount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), n)
        }
        public static var width: String { String(localized: "dashboard:width", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var youAreOwed: String { String(localized: "dashboard:youAreOwed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var youOwe: String { String(localized: "dashboard:youOwe", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Data {
        public static var backToSettings: String { String(localized: "data:backToSettings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var csvFile: String { String(localized: "data:csvFile", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var export: String { String(localized: "data:export", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var exportBtn: String { String(localized: "data:exportBtn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func exported(count: Int) -> String {
            String(format: String(localized: "data:exported", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func exportFailed(msg: String) -> String {
            String(format: String(localized: "data:exportFailed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), msg)
        }
        public static var exportNote: String { String(localized: "data:exportNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var fileFormat: String { String(localized: "data:fileFormat", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func firstIssues(issues: String) -> String {
            String(format: String(localized: "data:firstIssues", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), issues)
        }
        public static var footerNote: String { String(localized: "data:footerNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func foundPreview(count: Int, file: String) -> String {
            String(format: String(localized: "data:foundPreview", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count, file)
        }
        public static var `import`: String { String(localized: "data:import", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func importBtn(count: Int) -> String {
            String(format: String(localized: "data:importBtn", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var importing: String { String(localized: "data:importing", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var introPre: String { String(localized: "data:introPre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noExport: String { String(localized: "data:noExport", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noRows: String { String(localized: "data:noRows", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var preparing: String { String(localized: "data:preparing", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func readFail(msg: String) -> String {
            String(format: String(localized: "data:readFail", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), msg)
        }
        public static func resultLine(created: String, skipped: String, failed: String) -> String {
            String(format: String(localized: "data:resultLine", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), created, skipped, failed)
        }
        public static var skipDup: String { String(localized: "data:skipDup", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thAccount: String { String(localized: "data:thAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thAmount: String { String(localized: "data:thAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thCategory: String { String(localized: "data:thCategory", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thDate: String { String(localized: "data:thDate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thType: String { String(localized: "data:thType", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "data:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trialNote: String { String(localized: "data:trialNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Feedback {
        public static var areaAccountsCards: String { String(localized: "feedback:areaAccountsCards", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaAskSanvya: String { String(localized: "feedback:areaAskSanvya", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaBudgets: String { String(localized: "feedback:areaBudgets", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaDashboard: String { String(localized: "feedback:areaDashboard", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaFriendsSplits: String { String(localized: "feedback:areaFriendsSplits", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaGoals: String { String(localized: "feedback:areaGoals", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaInsights: String { String(localized: "feedback:areaInsights", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaInvestments: String { String(localized: "feedback:areaInvestments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaLabel: String { String(localized: "feedback:areaLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaLoans: String { String(localized: "feedback:areaLoans", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaOther: String { String(localized: "feedback:areaOther", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaPlaceholder: String { String(localized: "feedback:areaPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaSettingsBilling: String { String(localized: "feedback:areaSettingsBilling", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaSubscriptions: String { String(localized: "feedback:areaSubscriptions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaSyncOffline: String { String(localized: "feedback:areaSyncOffline", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var areaTransactions: String { String(localized: "feedback:areaTransactions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var autoIncluded: String { String(localized: "feedback:autoIncluded", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var bugPlaceholder: String { String(localized: "feedback:bugPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "feedback:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var done: String { String(localized: "feedback:done", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errNeedBug: String { String(localized: "feedback:errNeedBug", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errNeedSuggestion: String { String(localized: "feedback:errNeedSuggestion", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errSubmit: String { String(localized: "feedback:errSubmit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var includeLog: String { String(localized: "feedback:includeLog", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var includeLogHint: String { String(localized: "feedback:includeLogHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var intro: String { String(localized: "feedback:intro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindBug: String { String(localized: "feedback:kindBug", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindSuggestion: String { String(localized: "feedback:kindSuggestion", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sendAnother: String { String(localized: "feedback:sendAnother", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sendBug: String { String(localized: "feedback:sendBug", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sending: String { String(localized: "feedback:sending", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sendSuggestion: String { String(localized: "feedback:sendSuggestion", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var severityLabel: String { String(localized: "feedback:severityLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sevFatal: String { String(localized: "feedback:sevFatal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sevHigh: String { String(localized: "feedback:sevHigh", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sevLow: String { String(localized: "feedback:sevLow", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sevMedium: String { String(localized: "feedback:sevMedium", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var suggestionPlaceholder: String { String(localized: "feedback:suggestionPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thanksBug: String { String(localized: "feedback:thanksBug", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thanksBugBody: String { String(localized: "feedback:thanksBugBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thanksSuggestion: String { String(localized: "feedback:thanksSuggestion", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thanksSuggestionBody: String { String(localized: "feedback:thanksSuggestionBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "feedback:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var titlePlaceholder: String { String(localized: "feedback:titlePlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Goals {
        public static var achieved: String { String(localized: "goals:achieved", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var add: String { String(localized: "goals:add", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addFunds: String { String(localized: "goals:addFunds", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addGoal: String { String(localized: "goals:addGoal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addSavingsFirst: String { String(localized: "goals:addSavingsFirst", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func amount(currency: String) -> String {
            String(format: String(localized: "goals:amount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), currency)
        }
        public static var block: String { String(localized: "goals:block", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var blockFunds: String { String(localized: "goals:blockFunds", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "goals:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func celebrationAria(name: String) -> String {
            String(format: String(localized: "goals:celebrationAria", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var celebrationBody: String { String(localized: "goals:celebrationBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var celebrationHint: String { String(localized: "goals:celebrationHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var celebrationHintDrag: String { String(localized: "goals:celebrationHintDrag", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func celebrationName(name: String) -> String {
            String(format: String(localized: "goals:celebrationName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var celebrationTileFunded: String { String(localized: "goals:celebrationTileFunded", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var celebrationTilePct: String { String(localized: "goals:celebrationTilePct", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var celebrationTileTag: String { String(localized: "goals:celebrationTileTag", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var createFirst: String { String(localized: "goals:createFirst", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var delete: String { String(localized: "goals:delete", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "goals:deleteMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var deleteTitle: String { String(localized: "goals:deleteTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var edit: String { String(localized: "goals:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var efCheckbox: String { String(localized: "goals:efCheckbox", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var efFirst: String { String(localized: "goals:efFirst", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var efLiquid: String { String(localized: "goals:efLiquid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errName: String { String(localized: "goals:errName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errTarget: String { String(localized: "goals:errTarget", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var fromAccount: String { String(localized: "goals:fromAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var funded: String { String(localized: "goals:funded", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func goalActions(name: String) -> String {
            String(format: String(localized: "goals:goalActions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var goalName: String { String(localized: "goals:goalName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var goalReached: String { String(localized: "goals:goalReached", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func leftToTarget(amount: String) -> String {
            String(format: String(localized: "goals:leftToTarget", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var lockedUntil: String { String(localized: "goals:lockedUntil", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newGoal: String { String(localized: "goals:newGoal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noGoals: String { String(localized: "goals:noGoals", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "goals:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func target(currency: String) -> String {
            String(format: String(localized: "goals:target", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), currency)
        }
        public static var title: String { String(localized: "goals:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var willCap: String { String(localized: "goals:willCap", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Groups {
        public static func added(name: String) -> String {
            String(format: String(localized: "groups:added", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var addExistingFriends: String { String(localized: "groups:addExistingFriends", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func alreadyIn(name: String) -> String {
            String(format: String(localized: "groups:alreadyIn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static func autoSplitCreate(kind: String) -> String {
            String(format: String(localized: "groups:autoSplitCreate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), kind)
        }
        public static var autoSplitDates: String { String(localized: "groups:autoSplitDates", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func autoSplitDesc(start: String, end: String, kind: String) -> String {
            String(format: String(localized: "groups:autoSplitDesc", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), start, end, kind)
        }
        public static var autoSplitLabel: String { String(localized: "groups:autoSplitLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var autoSplitOn: String { String(localized: "groups:autoSplitOn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var autoSplitTag: String { String(localized: "groups:autoSplitTag", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var backToGroups: String { String(localized: "groups:backToGroups", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var backToGroupsLink: String { String(localized: "groups:backToGroupsLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "groups:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var copied: String { String(localized: "groups:copied", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var copyLink: String { String(localized: "groups:copyLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var create: String { String(localized: "groups:create", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var createFirst: String { String(localized: "groups:createFirst", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var creating: String { String(localized: "groups:creating", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var datesOptional: String { String(localized: "groups:datesOptional", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var delete: String { String(localized: "groups:delete", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "groups:deleteMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var deleteTitle: String { String(localized: "groups:deleteTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var edit: String { String(localized: "groups:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func editKind(kind: String) -> String {
            String(format: String(localized: "groups:editKind", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), kind)
        }
        public static var emailPlaceholder: String { String(localized: "groups:emailPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func error(msg: String) -> String {
            String(format: String(localized: "groups:error", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), msg)
        }
        public static var expenseFallback: String { String(localized: "groups:expenseFallback", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var expensesTitle: String { String(localized: "groups:expensesTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var friends: String { String(localized: "groups:friends", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupActions: String { String(localized: "groups:groupActions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupNamePlaceholder: String { String(localized: "groups:groupNamePlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupNotFound: String { String(localized: "groups:groupNotFound", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var invite: String { String(localized: "groups:invite", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func inviteAddEmail(email: String) -> String {
            String(format: String(localized: "groups:inviteAddEmail", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), email)
        }
        public static var inviteBody: String { String(localized: "groups:inviteBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func inviteCount(count: Int) -> String {
            String(format: String(localized: "groups:inviteCount", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func invitedAdded(count: Int) -> String {
            String(format: String(localized: "groups:invitedAdded", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func invitedFailed(names: String) -> String {
            String(format: String(localized: "groups:invitedFailed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), names)
        }
        public static func invitedLinks(count: Int) -> String {
            String(format: String(localized: "groups:invitedLinks", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func inviteNarrow(count: Int) -> String {
            String(format: String(localized: "groups:inviteNarrow", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var invitePlaceholder: String { String(localized: "groups:invitePlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func inviteTo(name: String) -> String {
            String(format: String(localized: "groups:inviteTo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var kindGroup: String { String(localized: "groups:kind.group", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindTrip: String { String(localized: "groups:kind.trip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func members(count: Int) -> String {
            String(format: String(localized: "groups:members", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var membersTitle: String { String(localized: "groups:membersTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var namePlaceholder: String { String(localized: "groups:namePlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var new: String { String(localized: "groups:new", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newGroupTrip: String { String(localized: "groups:newGroupTrip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noDates: String { String(localized: "groups:noDates", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noExpensesLink: String { String(localized: "groups:noExpensesLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func noExpensesPost(kind: String) -> String {
            String(format: String(localized: "groups:noExpensesPost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), kind)
        }
        public static var noExpensesPre: String { String(localized: "groups:noExpensesPre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noGroupsBody: String { String(localized: "groups:noGroupsBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noGroupsTitle: String { String(localized: "groups:noGroupsTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var orShareLink: String { String(localized: "groups:orShareLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func owesYouAmt(amount: String) -> String {
            String(format: String(localized: "groups:owesYouAmt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var remove: String { String(localized: "groups:remove", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "groups:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func settledBetween(from: String, to: String) -> String {
            String(format: String(localized: "groups:settledBetween", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), from, to)
        }
        public static func settledPaidYou(name: String) -> String {
            String(format: String(localized: "groups:settledPaidYou", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var settledPending: String { String(localized: "groups:settledPending", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settledTag: String { String(localized: "groups:settledTag", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settledTitle: String { String(localized: "groups:settledTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func settledYouPaid(name: String) -> String {
            String(format: String(localized: "groups:settledYouPaid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var someone: String { String(localized: "groups:someone", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "groups:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var totalSpent: String { String(localized: "groups:totalSpent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tripNamePlaceholder: String { String(localized: "groups:tripNamePlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var youOwe: String { String(localized: "groups:youOwe", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func youOweAmt(amount: String) -> String {
            String(format: String(localized: "groups:youOweAmt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var youreOwed: String { String(localized: "groups:youreOwed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Help {
        public static var footer: String { String(localized: "help:footer", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func noMatch(query: String) -> String {
            String(format: String(localized: "help:noMatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), query)
        }
        public static var searchPlaceholder: String { String(localized: "help:searchPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var subtitleLink: String { String(localized: "help:subtitleLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var subtitlePost: String { String(localized: "help:subtitlePost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var subtitlePre: String { String(localized: "help:subtitlePre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "help:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Insights {
        public static var feedBody: String { String(localized: "insights:feedBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var feedTitle: String { String(localized: "insights:feedTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var goPremium: String { String(localized: "insights:goPremium", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var statements: String { String(localized: "insights:statements", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "insights:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Investments {
        public static var addBankFirst: String { String(localized: "investments:addBankFirst", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var adding: String { String(localized: "investments:adding", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addInvAccount: String { String(localized: "investments:addInvAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addInvestment: String { String(localized: "investments:addInvestment", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func addTo(name: String) -> String {
            String(format: String(localized: "investments:addTo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var allExchanges: String { String(localized: "investments:allExchanges", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allInvestments: String { String(localized: "investments:allInvestments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allocation: String { String(localized: "investments:allocation", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allocationEmpty: String { String(localized: "investments:allocationEmpty", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allTime: String { String(localized: "investments:allTime", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var alreadyHold: String { String(localized: "investments:alreadyHold", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func amountInvested(cur: String) -> String {
            String(format: String(localized: "investments:amountInvested", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), cur)
        }
        public static func asOf(date: String) -> String {
            String(format: String(localized: "investments:asOf", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), date)
        }
        public static var assetClassCrypto: String { String(localized: "investments:assetClass.crypto", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var assetClassFd: String { String(localized: "investments:assetClass.fd", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var assetClassMf: String { String(localized: "investments:assetClass.mf", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var assetClassOther: String { String(localized: "investments:assetClass.other", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var assetClassSip: String { String(localized: "investments:assetClass.sip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var assetClassStock: String { String(localized: "investments:assetClass.stock", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var assumedGrowth: String { String(localized: "investments:assumedGrowth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func avgCost(cur: String) -> String {
            String(format: String(localized: "investments:avgCost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), cur)
        }
        public static var byExchangeScheme: String { String(localized: "investments:byExchangeScheme", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "investments:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var catalogSeedNote: String { String(localized: "investments:catalogSeedNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var currentValue: String { String(localized: "investments:currentValue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func currentValueCur(cur: String) -> String {
            String(format: String(localized: "investments:currentValueCur", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), cur)
        }
        public static func currentValueOptional(cur: String) -> String {
            String(format: String(localized: "investments:currentValueOptional", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), cur)
        }
        public static var debitsFrom: String { String(localized: "investments:debitsFrom", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func deductFrom(amount: String) -> String {
            String(format: String(localized: "investments:deductFrom", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var demat: String { String(localized: "investments:demat", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dividendFootnote: String { String(localized: "investments:dividendFootnote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dividendIncome: String { String(localized: "investments:dividendIncome", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func dividendsEarned(fy: String) -> String {
            String(format: String(localized: "investments:dividendsEarned", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), fy)
        }
        public static var dividendsNote: String { String(localized: "investments:dividendsNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var divPeriodAll: String { String(localized: "investments:divPeriod.all", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var divPeriodMonth: String { String(localized: "investments:divPeriod.month", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var divPeriodQuarter: String { String(localized: "investments:divPeriod.quarter", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var divPeriodWeek: String { String(localized: "investments:divPeriod.week", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var divPeriodYear: String { String(localized: "investments:divPeriod.year", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var edit: String { String(localized: "investments:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func eodNote(asOf: String) -> String {
            String(format: String(localized: "investments:eodNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), asOf)
        }
        public static var errAddFailed: String { String(localized: "investments:errAddFailed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errFundingAccount: String { String(localized: "investments:errFundingAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errHoldingNotFound: String { String(localized: "investments:errHoldingNotFound", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errInstrument: String { String(localized: "investments:errInstrument", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errInvalidQuantity: String { String(localized: "investments:errInvalidQuantity", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errName: String { String(localized: "investments:errName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errNoUser: String { String(localized: "investments:errNoUser", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errQuantity: String { String(localized: "investments:errQuantity", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errSaveFailed: String { String(localized: "investments:errSaveFailed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errSipAmount: String { String(localized: "investments:errSipAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errSipSource: String { String(localized: "investments:errSipSource", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var exchangeLabel: String { String(localized: "investments:exchangeLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var existingNote: String { String(localized: "investments:existingNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func fyLabel(start: String, end: String) -> String {
            String(format: String(localized: "investments:fyLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), start, end)
        }
        public static var gainLossByGroup: String { String(localized: "investments:gainLossByGroup", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var gainsEmpty: String { String(localized: "investments:gainsEmpty", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupTitleCrypto: String { String(localized: "investments:groupTitle.crypto", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupTitleFallback: String { String(localized: "investments:groupTitle.fallback", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupTitleFd: String { String(localized: "investments:groupTitle.fd", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupTitleMf: String { String(localized: "investments:groupTitle.mf", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupTitleOther: String { String(localized: "investments:groupTitle.other", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupTitleSip: String { String(localized: "investments:groupTitle.sip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupTitleStock: String { String(localized: "investments:groupTitle.stock", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupTitleStocksOther: String { String(localized: "investments:groupTitle.stocksOther", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var growthPlusDividends: String { String(localized: "investments:growthPlusDividends", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func holdingsCount(count: Int) -> String {
            String(format: String(localized: "investments:holdingsCount", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var horizon: String { String(localized: "investments:horizon", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var inOurList: String { String(localized: "investments:inOurList", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var insights: String { String(localized: "investments:insights", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var instrumentSearch: String { String(localized: "investments:instrumentSearch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var instrumentSource: String { String(localized: "investments:instrumentSource", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var interestPa: String { String(localized: "investments:interestPa", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var invested: String { String(localized: "investments:invested", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func investedLabel(amount: String) -> String {
            String(format: String(localized: "investments:investedLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var investmentAccount: String { String(localized: "investments:investmentAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func inYears(years: String) -> String {
            String(format: String(localized: "investments:inYears", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), years)
        }
        public static var last12Months: String { String(localized: "investments:last12Months", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var ltpLabel: String { String(localized: "investments:ltpLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var matures: String { String(localized: "investments:matures", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var maturityDate: String { String(localized: "investments:maturityDate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func monthlyContribution(cur: String) -> String {
            String(format: String(localized: "investments:monthlyContribution", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), cur)
        }
        public static func nameLabel(type: String) -> String {
            String(format: String(localized: "investments:nameLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), type)
        }
        public static func navAvgCost(cur: String) -> String {
            String(format: String(localized: "investments:navAvgCost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), cur)
        }
        public static func navCost(cur: String) -> String {
            String(format: String(localized: "investments:navCost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), cur)
        }
        public static var newFund: String { String(localized: "investments:newFund", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newOrHold: String { String(localized: "investments:newOrHold", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var next12Months: String { String(localized: "investments:next12Months", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var nextSipDate: String { String(localized: "investments:nextSipDate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noDividendData: String { String(localized: "investments:noDividendData", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noFundAccount: String { String(localized: "investments:noFundAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noInstrumentMatches: String { String(localized: "investments:noInstrumentMatches", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noInvAccountBodyPost: String { String(localized: "investments:noInvAccountBodyPost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noInvAccountBodyPre: String { String(localized: "investments:noInvAccountBodyPre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noInvAccountTitle: String { String(localized: "investments:noInvAccountTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noInvestments: String { String(localized: "investments:noInvestments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var notListed: String { String(localized: "investments:notListed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func overFunds(account: String) -> String {
            String(format: String(localized: "investments:overFunds", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), account)
        }
        public static func perAnnum(rate: String) -> String {
            String(format: String(localized: "investments:perAnnum", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), rate)
        }
        public static var projectedValue: String { String(localized: "investments:projectedValue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var projectedWealth: String { String(localized: "investments:projectedWealth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var projectionFootnote: String { String(localized: "investments:projectionFootnote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var qty: String { String(localized: "investments:qty", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var quantity: String { String(localized: "investments:quantity", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reinvestDividends: String { String(localized: "investments:reinvestDividends", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func reinvestYield(pct: String) -> String {
            String(format: String(localized: "investments:reinvestYield", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), pct)
        }
        public static var remove: String { String(localized: "investments:remove", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func removeMsg(label: String) -> String {
            String(format: String(localized: "investments:removeMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), label)
        }
        public static var removeTitle: String { String(localized: "investments:removeTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "investments:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var selectAccount: String { String(localized: "investments:selectAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func sipAmount(cur: String) -> String {
            String(format: String(localized: "investments:sipAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), cur)
        }
        public static var sipDebitDay: String { String(localized: "investments:sipDebitDay", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sipDebitDayHint: String { String(localized: "investments:sipDebitDayHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sipFreqMonthly: String { String(localized: "investments:sipFreq.monthly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sipFreqWeekly: String { String(localized: "investments:sipFreq.weekly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sipFreqYearly: String { String(localized: "investments:sipFreq.yearly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sipFrequency: String { String(localized: "investments:sipFrequency", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sipLine: String { String(localized: "investments:sipLine", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func sipNote(amount: String, account: String) -> String {
            String(format: String(localized: "investments:sipNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount, account)
        }
        public static var sipStartDate: String { String(localized: "investments:sipStartDate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var startTypingInstrument: String { String(localized: "investments:startTypingInstrument", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var stopSip: String { String(localized: "investments:stopSip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var stopSipMsg: String { String(localized: "investments:stopSipMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var stopSipTitle: String { String(localized: "investments:stopSipTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var syncNote: String { String(localized: "investments:syncNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var theAmount: String { String(localized: "investments:theAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var thisAccount: String { String(localized: "investments:thisAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "investments:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var total: String { String(localized: "investments:total", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var totalGainLoss: String { String(localized: "investments:totalGainLoss", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var units: String { String(localized: "investments:units", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unitWordCoins: String { String(localized: "investments:unitWord.coins", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unitWordShares: String { String(localized: "investments:unitWord.shares", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unitWordUnits: String { String(localized: "investments:unitWord.units", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var untracked: String { String(localized: "investments:untracked", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var valueLabel: String { String(localized: "investments:valueLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var youPutIn: String { String(localized: "investments:youPutIn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Join {
        public static var missingToken: String { String(localized: "join:missingToken", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var needAuth: String { String(localized: "join:needAuth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var opening: String { String(localized: "join:opening", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signInCreate: String { String(localized: "join:signInCreate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "join:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Labels {
        public static var addLabel: String { String(localized: "labels:addLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var backToSettings: String { String(localized: "labels:backToSettings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "labels:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var delete: String { String(localized: "labels:delete", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "labels:deleteMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var deleteTitle: String { String(localized: "labels:deleteTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var edit: String { String(localized: "labels:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newLabel: String { String(localized: "labels:newLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noLabels: String { String(localized: "labels:noLabels", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "labels:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var searchPlaceholder: String { String(localized: "labels:searchPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "labels:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Loans {
        public static var active: String { String(localized: "loans:active", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var add: String { String(localized: "loans:add", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addEmiHint: String { String(localized: "loans:addEmiHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addFirst: String { String(localized: "loans:addFirst", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addInterestHint: String { String(localized: "loans:addInterestHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addLoan: String { String(localized: "loans:addLoan", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var alsoRecord: String { String(localized: "loans:alsoRecord", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var amortPrincipalOnly: String { String(localized: "loans:amortPrincipalOnly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var amortTitle: String { String(localized: "loans:amortTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var amortWithInterest: String { String(localized: "loans:amortWithInterest", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func autoCalcEdit(amount: String) -> String {
            String(format: String(localized: "loans:autoCalcEdit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var autoCalcHint: String { String(localized: "loans:autoCalcHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func autoCalcWas(amount: String) -> String {
            String(format: String(localized: "loans:autoCalcWas", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var autoMarked: String { String(localized: "loans:autoMarked", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func autoMarkedTitle(date: String) -> String {
            String(format: String(localized: "loans:autoMarkedTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), date)
        }
        public static var autoMarkHint: String { String(localized: "loans:autoMarkHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var autoMarkLabel: String { String(localized: "loans:autoMarkLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var autoMarkOff: String { String(localized: "loans:autoMarkOff", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var autoMarkOn: String { String(localized: "loans:autoMarkOn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var autoMarkTitle: String { String(localized: "loans:autoMarkTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var balance: String { String(localized: "loans:balance", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "loans:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cardEmisPaid: String { String(localized: "loans:cardEmisPaid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cardInterestRate: String { String(localized: "loans:cardInterestRate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cardMonthlyEmi: String { String(localized: "loans:cardMonthlyEmi", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cardPrincipal: String { String(localized: "loans:cardPrincipal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cardSuffix: String { String(localized: "loans:cardSuffix", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var chargedTo: String { String(localized: "loans:chargedTo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var chargedToCardHint: String { String(localized: "loans:chargedToCardHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var chargedToHint: String { String(localized: "loans:chargedToHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var closed: String { String(localized: "loans:closed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var currentInterest: String { String(localized: "loans:currentInterest", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var delete: String { String(localized: "loans:delete", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "loans:deleteMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var deleteTitle: String { String(localized: "loans:deleteTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dontRecord: String { String(localized: "loans:dontRecord", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dueBlankHint: String { String(localized: "loans:dueBlankHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func dueDate(date: String) -> String {
            String(format: String(localized: "loans:dueDate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), date)
        }
        public static var dueDay: String { String(localized: "loans:dueDay", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func dueLine(date: String) -> String {
            String(format: String(localized: "loans:dueLine", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), date)
        }
        public static func dueOnEach(ord: String, n: String) -> String {
            String(format: String(localized: "loans:dueOnEach", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), ord, n)
        }
        public static var edit: String { String(localized: "loans:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var editTitle: String { String(localized: "loans:editTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emiAmount: String { String(localized: "loans:emiAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func emiPaidCount(paid: String, tenure: String) -> String {
            String(format: String(localized: "loans:emiPaidCount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), paid, tenure)
        }
        public static var emiThisMonth: String { String(localized: "loans:emiThisMonth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var fixed: String { String(localized: "loans:fixed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var interestAmount: String { String(localized: "loans:interestAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var interestPa: String { String(localized: "loans:interestPa", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var interestType: String { String(localized: "loans:interestType", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var lender: String { String(localized: "loans:lender", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var loading: String { String(localized: "loans:loading", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var loanAmount: String { String(localized: "loans:loanAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func loanCount(count: Int) -> String {
            String(format: String(localized: "loans:loanCount", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var loanFallback: String { String(localized: "loans:loanFallback", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func markEmiPaid(n: String) -> String {
            String(format: String(localized: "loans:markEmiPaid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), n)
        }
        public static var markPaid: String { String(localized: "loans:markPaid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var markPaidRecord: String { String(localized: "loans:markPaidRecord", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var markPaidTitle: String { String(localized: "loans:markPaidTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func monthlyEmi(cur: String) -> String {
            String(format: String(localized: "loans:monthlyEmi", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), cur)
        }
        public static var nextEmiDue: String { String(localized: "loans:nextEmiDue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noLoansBody: String { String(localized: "loans:noLoansBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noLoansTitle: String { String(localized: "loans:noLoansTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var notExist: String { String(localized: "loans:notExist", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var notLinked: String { String(localized: "loans:notLinked", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func nthEmi(ord: String, n: String) -> String {
            String(format: String(localized: "loans:nthEmi", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), ord, n)
        }
        public static var off: String { String(localized: "loans:off", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var on: String { String(localized: "loans:on", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func onDate(date: String) -> String {
            String(format: String(localized: "loans:onDate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), date)
        }
        public static var paidCheck: String { String(localized: "loans:paidCheck", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func paidCount(paid: String) -> String {
            String(format: String(localized: "loans:paidCount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), paid)
        }
        public static var paidOn: String { String(localized: "loans:paidOn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var paidSoFar: String { String(localized: "loans:paidSoFar", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var paidTitle: String { String(localized: "loans:paidTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func perAnnum(rate: String) -> String {
            String(format: String(localized: "loans:perAnnum", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), rate)
        }
        public static func postsExpense(amount: String, date: String) -> String {
            String(format: String(localized: "loans:postsExpense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount, date)
        }
        public static var postsToCard: String { String(localized: "loans:postsToCard", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func principal(cur: String) -> String {
            String(format: String(localized: "loans:principal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), cur)
        }
        public static var principalAmount: String { String(localized: "loans:principalAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var rateVariableSuffix: String { String(localized: "loans:rateVariableSuffix", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var remaining: String { String(localized: "loans:remaining", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func remainingEmis(count: String) -> String {
            String(format: String(localized: "loans:remainingEmis", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var remembersAccount: String { String(localized: "loans:remembersAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "loans:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var savingEllipsis: String { String(localized: "loans:savingEllipsis", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var startedOn: String { String(localized: "loans:startedOn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tenureMonths: String { String(localized: "loans:tenureMonths", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "loans:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var totalEmisMonth: String { String(localized: "loans:totalEmisMonth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var totalInterestSchedule: String { String(localized: "loans:totalInterestSchedule", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var useIt: String { String(localized: "loans:useIt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var variable: String { String(localized: "loans:variable", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var variableAddTenure: String { String(localized: "loans:variableAddTenure", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var variableEditNote: String { String(localized: "loans:variableEditNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var variableNote: String { String(localized: "loans:variableNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var variableNoteBold: String { String(localized: "loans:variableNoteBold", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var variableNotePost: String { String(localized: "loans:variableNotePost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var variableNotePre: String { String(localized: "loans:variableNotePre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var variableTitle: String { String(localized: "loans:variableTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var varies: String { String(localized: "loans:varies", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Login {
        public static var accountCreated: String { String(localized: "login:accountCreated", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var back: String { String(localized: "login:back", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var backToSignin: String { String(localized: "login:backToSignin", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var codePlaceholder: String { String(localized: "login:codePlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirmNewPw: String { String(localized: "login:confirmNewPw", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirmPassword: String { String(localized: "login:confirmPassword", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var `continue`: String { String(localized: "login:continue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var continueGoogle: String { String(localized: "login:continueGoogle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var displayName: String { String(localized: "login:displayName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emailLabel: String { String(localized: "login:emailLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emailVerified: String { String(localized: "login:emailVerified", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var encNote: String { String(localized: "login:encNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errEmail: String { String(localized: "login:errEmail", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errName: String { String(localized: "login:errName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errOtp: String { String(localized: "login:errOtp", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errPwLen: String { String(localized: "login:errPwLen", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errPwMatch: String { String(localized: "login:errPwMatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errResetEmail: String { String(localized: "login:errResetEmail", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errSignin: String { String(localized: "login:errSignin", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var forgotPassword: String { String(localized: "login:forgotPassword", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var friendlyExists: String { String(localized: "login:friendlyExists", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var friendlyExpired: String { String(localized: "login:friendlyExpired", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var friendlyInvalidCreds: String { String(localized: "login:friendlyInvalidCreds", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var friendlyNotConfirmed: String { String(localized: "login:friendlyNotConfirmed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newCodeSent: String { String(localized: "login:newCodeSent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newPw: String { String(localized: "login:newPw", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newPwTitle: String { String(localized: "login:newPwTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var or: String { String(localized: "login:or", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var passwordPlaceholder: String { String(localized: "login:passwordPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pwUpdated: String { String(localized: "login:pwUpdated", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var registerSub: String { String(localized: "login:registerSub", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var registerTitle: String { String(localized: "login:registerTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var resend: String { String(localized: "login:resend", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var resetSub: String { String(localized: "login:resetSub", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var resetTitle: String { String(localized: "login:resetTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var saving: String { String(localized: "login:saving", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sendResetCode: String { String(localized: "login:sendResetCode", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func sentCode(email: String) -> String {
            String(format: String(localized: "login:sentCode", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), email)
        }
        public static func sentReset(email: String) -> String {
            String(format: String(localized: "login:sentReset", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), email)
        }
        public static var setNewPwDefault: String { String(localized: "login:setNewPwDefault", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signedIn: String { String(localized: "login:signedIn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signInBtn: String { String(localized: "login:signInBtn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signinSub: String { String(localized: "login:signinSub", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signinTitle: String { String(localized: "login:signinTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signUpGoogle: String { String(localized: "login:signUpGoogle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var switchToRegister: String { String(localized: "login:switchToRegister", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var switchToSignin: String { String(localized: "login:switchToSignin", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var updatePw: String { String(localized: "login:updatePw", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var verifyCode: String { String(localized: "login:verifyCode", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var verifyCreate: String { String(localized: "login:verifyCreate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var verifying: String { String(localized: "login:verifying", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var verifyTitle: String { String(localized: "login:verifyTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Notifications {
        public static func daysAgo(count: String) -> String {
            String(format: String(localized: "notifications:daysAgo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var dismiss: String { String(localized: "notifications:dismiss", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyBody: String { String(localized: "notifications:emptyBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyTitle: String { String(localized: "notifications:emptyTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var enableCta: String { String(localized: "notifications:enableCta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func hoursAgo(count: String) -> String {
            String(format: String(localized: "notifications:hoursAgo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var justNow: String { String(localized: "notifications:justNow", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var markAllRead: String { String(localized: "notifications:markAllRead", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func minutesAgo(count: String) -> String {
            String(format: String(localized: "notifications:minutesAgo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var settings: String { String(localized: "notifications:settings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "notifications:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Onboarding {
        public static var createAccount: String { String(localized: "onboarding:createAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var footer: String { String(localized: "onboarding:footer", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var guestErr: String { String(localized: "onboarding:guestErr", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var installApp: String { String(localized: "onboarding:installApp", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var installTitle: String { String(localized: "onboarding:installTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var next: String { String(localized: "onboarding:next", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signIn: String { String(localized: "onboarding:signIn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var skip: String { String(localized: "onboarding:skip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides0Body: String { String(localized: "onboarding:slides.0.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides0Title: String { String(localized: "onboarding:slides.0.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides1Body: String { String(localized: "onboarding:slides.1.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides1Title: String { String(localized: "onboarding:slides.1.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides2Body: String { String(localized: "onboarding:slides.2.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides2Title: String { String(localized: "onboarding:slides.2.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides3Body: String { String(localized: "onboarding:slides.3.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides3Title: String { String(localized: "onboarding:slides.3.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides4Body: String { String(localized: "onboarding:slides.4.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides4Title: String { String(localized: "onboarding:slides.4.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides5Body: String { String(localized: "onboarding:slides.5.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides5Title: String { String(localized: "onboarding:slides.5.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides6Body: String { String(localized: "onboarding:slides.6.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var slides6Title: String { String(localized: "onboarding:slides.6.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var starting: String { String(localized: "onboarding:starting", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tryGuest: String { String(localized: "onboarding:tryGuest", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAccBalHelp: String { String(localized: "onboarding:wt.acc.balHelp", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAccBalLabel: String { String(localized: "onboarding:wt.acc.balLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAccCta: String { String(localized: "onboarding:wt.acc.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAccEg1: String { String(localized: "onboarding:wt.acc.eg1", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAccEg2: String { String(localized: "onboarding:wt.acc.eg2", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAccNameLabel: String { String(localized: "onboarding:wt.acc.nameLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAccP1: String { String(localized: "onboarding:wt.acc.p1", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAccP2: String { String(localized: "onboarding:wt.acc.p2", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAccTitle: String { String(localized: "onboarding:wt.acc.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAskP1: String { String(localized: "onboarding:wt.ask.p1", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAskP2: String { String(localized: "onboarding:wt.ask.p2", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAskPrivacy: String { String(localized: "onboarding:wt.ask.privacy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtAskTitle: String { String(localized: "onboarding:wt.ask.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDialogLabel: String { String(localized: "onboarding:wt.dialogLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDoneBudgetBody: String { String(localized: "onboarding:wt.done.budgetBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDoneBudgetTitle: String { String(localized: "onboarding:wt.done.budgetTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDoneCta: String { String(localized: "onboarding:wt.done.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDoneDashBody: String { String(localized: "onboarding:wt.done.dashBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDoneDashTitle: String { String(localized: "onboarding:wt.done.dashTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDoneMore: String { String(localized: "onboarding:wt.done.more", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDonePrivacy: String { String(localized: "onboarding:wt.done.privacy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDoneTitle: String { String(localized: "onboarding:wt.done.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDoneTxnBody: String { String(localized: "onboarding:wt.done.txnBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtDoneTxnTitle: String { String(localized: "onboarding:wt.done.txnTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtGuestCta: String { String(localized: "onboarding:wt.guest.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtGuestLater: String { String(localized: "onboarding:wt.guest.later", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtGuestP1: String { String(localized: "onboarding:wt.guest.p1", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtGuestTitle: String { String(localized: "onboarding:wt.guest.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtInsightsEg: String { String(localized: "onboarding:wt.insights.eg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtInsightsP1: String { String(localized: "onboarding:wt.insights.p1", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtInsightsP2: String { String(localized: "onboarding:wt.insights.p2", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtInsightsTitle: String { String(localized: "onboarding:wt.insights.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtIntroCta: String { String(localized: "onboarding:wt.intro.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtIntroP1: String { String(localized: "onboarding:wt.intro.p1", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtIntroP2: String { String(localized: "onboarding:wt.intro.p2", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtIntroP3: String { String(localized: "onboarding:wt.intro.p3", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtIntroP4: String { String(localized: "onboarding:wt.intro.p4", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtIntroTitle: String { String(localized: "onboarding:wt.intro.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtLater: String { String(localized: "onboarding:wt.later", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtNext: String { String(localized: "onboarding:wt.next", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtPlanCta: String { String(localized: "onboarding:wt.plan.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtPlanFree: String { String(localized: "onboarding:wt.plan.free", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func wtPlanPerMonth(amount: String) -> String {
            String(format: String(localized: "onboarding:wt.plan.perMonth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static func wtPlanQuota(count: String) -> String {
            String(format: String(localized: "onboarding:wt.plan.quota", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var wtPlanSee: String { String(localized: "onboarding:wt.plan.see", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtPlanTitle: String { String(localized: "onboarding:wt.plan.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtPlanTitleTrial: String { String(localized: "onboarding:wt.plan.titleTrial", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtPlanTrial: String { String(localized: "onboarding:wt.plan.trial", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func wtProgress(step: String, of: String) -> String {
            String(format: String(localized: "onboarding:wt.progress", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), step, of)
        }
        public static var wtSaving: String { String(localized: "onboarding:wt.saving", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtSkip: String { String(localized: "onboarding:wt.skip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtSpendAmountLabel: String { String(localized: "onboarding:wt.spend.amountLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtSpendCta: String { String(localized: "onboarding:wt.spend.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtSpendP1: String { String(localized: "onboarding:wt.spend.p1", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtSpendP2: String { String(localized: "onboarding:wt.spend.p2", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtSpendP3: String { String(localized: "onboarding:wt.spend.p3", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtSpendTitle: String { String(localized: "onboarding:wt.spend.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtSpendWhatEg: String { String(localized: "onboarding:wt.spend.whatEg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wtSpendWhatLabel: String { String(localized: "onboarding:wt.spend.whatLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Payments {
        public static func confirmClaim(name: String) -> String {
            String(format: String(localized: "payments:confirm.claim", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var confirmIntro: String { String(localized: "payments:confirm.intro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirmNo: String { String(localized: "payments:confirm.no", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirmNoAccount: String { String(localized: "payments:confirm.noAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirmPendingChip: String { String(localized: "payments:confirm.pendingChip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirmReceivedInto: String { String(localized: "payments:confirm.receivedInto", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func confirmReference(ref: String) -> String {
            String(format: String(localized: "payments:confirm.reference", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), ref)
        }
        public static var confirmTitle: String { String(localized: "payments:confirm.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirmYes: String { String(localized: "payments:confirm.yes", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAfterPaying: String { String(localized: "payments:pay.afterPaying", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payBack: String { String(localized: "payments:pay.back", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payButton: String { String(localized: "payments:pay.button", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payCopied: String { String(localized: "payments:pay.copied", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payCopyAmount: String { String(localized: "payments:pay.copyAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payCopyId: String { String(localized: "payments:pay.copyId", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payDidntOpen: String { String(localized: "payments:pay.didntOpen", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payManualTitle: String { String(localized: "payments:pay.manualTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payMarkPaid: String { String(localized: "payments:pay.markPaid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func payNoCallbackNote(name: String) -> String {
            String(format: String(localized: "payments:pay.noCallbackNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static func payNoHandle(name: String) -> String {
            String(format: String(localized: "payments:pay.noHandle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var payOpenApp: String { String(localized: "payments:pay.openApp", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payPayingTo: String { String(localized: "payments:pay.payingTo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payPreparing: String { String(localized: "payments:pay.preparing", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payQrAlt: String { String(localized: "payments:pay.qrAlt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payQrHintMobile: String { String(localized: "payments:pay.qrHintMobile", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payScanHint: String { String(localized: "payments:pay.scanHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneAmount: String { String(localized: "payments:payAnyone.amount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneCancelScan: String { String(localized: "payments:payAnyone.cancelScan", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func payAnyoneClaimsName(name: String) -> String {
            String(format: String(localized: "payments:payAnyone.claimsName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var payAnyoneClose: String { String(localized: "payments:payAnyone.close", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneErrBadVpa: String { String(localized: "payments:payAnyone.err.bad_vpa", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneErrEmpty: String { String(localized: "payments:payAnyone.err.empty", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneErrEmvco: String { String(localized: "payments:payAnyone.err.emvco", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneErrNotUpi: String { String(localized: "payments:payAnyone.err.not_upi", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneErrOther: String { String(localized: "payments:payAnyone.err.other", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneErrUnsupportedCurrency: String { String(localized: "payments:payAnyone.err.unsupported_currency", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneFootnote: String { String(localized: "payments:payAnyone.footnote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneNotePlaceholder: String { String(localized: "payments:payAnyone.notePlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyonePay: String { String(localized: "payments:payAnyone.pay", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyonePayAmount: String { String(localized: "payments:payAnyone.payAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneScanCta: String { String(localized: "payments:payAnyone.scanCta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneScanHint: String { String(localized: "payments:payAnyone.scanHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneSubtitle: String { String(localized: "payments:payAnyone.subtitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneTitle: String { String(localized: "payments:payAnyone.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneUpiId: String { String(localized: "payments:payAnyone.upiId", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsCurrent: String { String(localized: "payments:settings.current", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsGuestBlocked: String { String(localized: "payments:settings.guestBlocked", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsHideLog: String { String(localized: "payments:settings.hideLog", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsIntro: String { String(localized: "payments:settings.intro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsInvalid: String { String(localized: "payments:settings.invalid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsLabel: String { String(localized: "payments:settings.label", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsPlaceholder: String { String(localized: "payments:settings.placeholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsPrivacy: String { String(localized: "payments:settings.privacy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsRemove: String { String(localized: "payments:settings.remove", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsReplace: String { String(localized: "payments:settings.replace", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsSave: String { String(localized: "payments:settings.save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func settingsShowLog(count: String) -> String {
            String(format: String(localized: "payments:settings.showLog", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var settingsSomeone: String { String(localized: "payments:settings.someone", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsTitle: String { String(localized: "payments:settings.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsUpdate: String { String(localized: "payments:settings.update", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func settingsWillShow(masked: String) -> String {
            String(format: String(localized: "payments:settings.willShow", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), masked)
        }
        public static var someone: String { String(localized: "payments:someone", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Receipts {
        public static var breakdownEveryone: String { String(localized: "receipts:breakdown.everyone", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var breakdownHide: String { String(localized: "receipts:breakdown.hide", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func breakdownPersonTotal(name: String) -> String {
            String(format: String(localized: "receipts:breakdown.personTotal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var breakdownShow: String { String(localized: "receipts:breakdown.show", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureAiNote: String { String(localized: "receipts:capture.aiNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func captureCreditsLeft(count: String) -> String {
            String(format: String(localized: "receipts:capture.creditsLeft", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var captureDropHint: String { String(localized: "receipts:capture.dropHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureEditManually: String { String(localized: "receipts:capture.editManually", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureImproveWithAi: String { String(localized: "receipts:capture.improveWithAi", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureIntro: String { String(localized: "receipts:capture.intro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureNoCredits: String { String(localized: "receipts:capture.noCredits", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var capturePasswordPlaceholder: String { String(localized: "receipts:capture.passwordPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var capturePdfPassword: String { String(localized: "receipts:capture.pdfPassword", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var capturePreviewAlt: String { String(localized: "receipts:capture.previewAlt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var capturePrivacy: String { String(localized: "receipts:capture.privacy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureRetake: String { String(localized: "receipts:capture.retake", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureSeePlans: String { String(localized: "receipts:capture.seePlans", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureTakePhoto: String { String(localized: "receipts:capture.takePhoto", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureTitle: String { String(localized: "receipts:capture.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureUnclearMismatch: String { String(localized: "receipts:capture.unclear.mismatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureUnclearNoLines: String { String(localized: "receipts:capture.unclear.noLines", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureUnclearNoTotal: String { String(localized: "receipts:capture.unclear.noTotal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureUnclearTitle: String { String(localized: "receipts:capture.unclear.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureUnlock: String { String(localized: "receipts:capture.unlock", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var captureUpload: String { String(localized: "receipts:capture.upload", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errorsPdfLocked: String { String(localized: "receipts:errors.pdfLocked", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errorsPdfNoText: String { String(localized: "receipts:errors.pdfNoText", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errorsPdfUnreadable: String { String(localized: "receipts:errors.pdfUnreadable", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var errorsUnsupportedFile: String { String(localized: "receipts:errors.unsupportedFile", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindDiscount: String { String(localized: "receipts:kind.discount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindItem: String { String(localized: "receipts:kind.item", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindServiceCharge: String { String(localized: "receipts:kind.service_charge", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindTax: String { String(localized: "receipts:kind.tax", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindTip: String { String(localized: "receipts:kind.tip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var modeEqual: String { String(localized: "receipts:mode.equal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var modeExact: String { String(localized: "receipts:mode.exact", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var modePercent: String { String(localized: "receipts:mode.percent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var modeProportional: String { String(localized: "receipts:mode.proportional", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var modeQuantity: String { String(localized: "receipts:mode.quantity", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var premiumBody: String { String(localized: "receipts:premium.body", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var premiumCta: String { String(localized: "receipts:premium.cta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var premiumTitle: String { String(localized: "receipts:premium.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewAccount: String { String(localized: "receipts:review.account", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewAddCharge: String { String(localized: "receipts:review.addCharge", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func reviewAddDifference(amount: String) -> String {
            String(format: String(localized: "receipts:review.addDifference", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var reviewAddItem: String { String(localized: "receipts:review.addItem", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewAmount: String { String(localized: "receipts:review.amount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func reviewBalanced(total: String) -> String {
            String(format: String(localized: "receipts:review.balanced", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), total)
        }
        public static var reviewCategory: String { String(localized: "receipts:review.category", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewContinueToSplit: String { String(localized: "receipts:review.continueToSplit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewCorrupt: String { String(localized: "receipts:review.corrupt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewDate: String { String(localized: "receipts:review.date", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewDescription: String { String(localized: "receipts:review.description", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewGroup: String { String(localized: "receipts:review.group", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewIntro: String { String(localized: "receipts:review.intro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewItems: String { String(localized: "receipts:review.items", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewJustRecord: String { String(localized: "receipts:review.justRecord", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewKind: String { String(localized: "receipts:review.kind", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func reviewLineCount(count: Int) -> String {
            String(format: String(localized: "receipts:review.lineCount", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var reviewMerchant: String { String(localized: "receipts:review.merchant", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewMerchantPlaceholder: String { String(localized: "receipts:review.merchantPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewMustBalance: String { String(localized: "receipts:review.mustBalance", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewNeedTotal: String { String(localized: "receipts:review.needTotal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewNewGroup: String { String(localized: "receipts:review.newGroup", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewNewGroupName: String { String(localized: "receipts:review.newGroupName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewNewGroupPlaceholder: String { String(localized: "receipts:review.newGroupPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewNoCategory: String { String(localized: "receipts:review.noCategory", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewNotFound: String { String(localized: "receipts:review.notFound", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func reviewOffBy(computed: String, stated: String) -> String {
            String(format: String(localized: "receipts:review.offBy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), computed, stated)
        }
        public static var reviewPickGroup: String { String(localized: "receipts:review.pickGroup", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewQty: String { String(localized: "receipts:review.qty", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewRemoveLine: String { String(localized: "receipts:review.removeLine", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewSave: String { String(localized: "receipts:review.save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewSplitIt: String { String(localized: "receipts:review.splitIt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewSplitNote: String { String(localized: "receipts:review.splitNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewSubtotalItems: String { String(localized: "receipts:review.subtotalItems", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewTitle: String { String(localized: "receipts:review.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewTotal: String { String(localized: "receipts:review.total", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reviewUnmatched: String { String(localized: "receipts:review.unmatched", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func reviewUseComputed(amount: String) -> String {
            String(format: String(localized: "receipts:review.useComputed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var splitCorrupt: String { String(localized: "receipts:split.corrupt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitEveryoneAll: String { String(localized: "receipts:split.everyoneAll", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func splitExactMismatch(diff: String) -> String {
            String(format: String(localized: "receipts:split.exactMismatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), diff)
        }
        public static var splitFixLines: String { String(localized: "receipts:split.fixLines", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitIntro: String { String(localized: "receipts:split.intro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitNeedsSomeone: String { String(localized: "receipts:split.needsSomeone", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitNotFound: String { String(localized: "receipts:split.notFound", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitOnlyMe: String { String(localized: "receipts:split.onlyMe", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func splitPercentMismatch(pct: String) -> String {
            String(format: String(localized: "receipts:split.percentMismatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), pct)
        }
        public static func splitQtyLabel(qty: String, unit: String) -> String {
            String(format: String(localized: "receipts:split.qtyLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), qty, unit)
        }
        public static func splitQtyMismatch(got: String, want: String) -> String {
            String(format: String(localized: "receipts:split.qtyMismatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), got, want)
        }
        public static var splitQuick: String { String(localized: "receipts:split.quick", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitSave: String { String(localized: "receipts:split.save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitSomeone: String { String(localized: "receipts:split.someone", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitTitle: String { String(localized: "receipts:split.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitTotal: String { String(localized: "receipts:split.total", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitYou: String { String(localized: "receipts:split.you", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var stageDone: String { String(localized: "receipts:stage.done", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var stagePreparing: String { String(localized: "receipts:stage.preparing", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var stageReading: String { String(localized: "receipts:stage.reading", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var stageUnderstanding: String { String(localized: "receipts:stage.understanding", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Recurring {
        public static func actions(name: String) -> String {
            String(format: String(localized: "recurring:actions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var add: String { String(localized: "recurring:add", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var alertTime: String { String(localized: "recurring:alertTime", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var amountLabel: String { String(localized: "recurring:amountLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var autoPosts: String { String(localized: "recurring:autoPosts", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "recurring:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirm: String { String(localized: "recurring:confirm", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var create: String { String(localized: "recurring:create", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dueNow: String { String(localized: "recurring:dueNow", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func dueOn(date: String) -> String {
            String(format: String(localized: "recurring:dueOn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), date)
        }
        public static var edit: String { String(localized: "recurring:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyIncome: String { String(localized: "recurring:emptyIncome", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyPayment: String { String(localized: "recurring:emptyPayment", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptySaving: String { String(localized: "recurring:emptySaving", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var freqDaily: String { String(localized: "recurring:freq.daily", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var freqMonthly: String { String(localized: "recurring:freq.monthly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var freqWeekly: String { String(localized: "recurring:freq.weekly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var freqYearly: String { String(localized: "recurring:freq.yearly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupDelete: String { String(localized: "recurring:groupDelete", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupDeleteEmpty: String { String(localized: "recurring:groupDeleteEmpty", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupDeleteLast: String { String(localized: "recurring:groupDeleteLast", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func groupDeleteMove(count: Int) -> String {
            String(format: String(localized: "recurring:groupDeleteMove", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func groupDeleteTitle(name: String) -> String {
            String(format: String(localized: "recurring:groupDeleteTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var groupEmpty: String { String(localized: "recurring:groupEmpty", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupNewCta: String { String(localized: "recurring:groupNewCta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var income: String { String(localized: "recurring:income", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var incomes: String { String(localized: "recurring:incomes", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func itemCount(count: Int) -> String {
            String(format: String(localized: "recurring:itemCount", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var netMonthly: String { String(localized: "recurring:netMonthly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func next(date: String) -> String {
            String(format: String(localized: "recurring:next", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), date)
        }
        public static var payment: String { String(localized: "recurring:payment", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payments: String { String(localized: "recurring:payments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var perMonth: String { String(localized: "recurring:perMonth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var perMonthLabel: String { String(localized: "recurring:perMonthLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var postNow: String { String(localized: "recurring:postNow", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var record: String { String(localized: "recurring:record", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var remove: String { String(localized: "recurring:remove", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func removeMsg(name: String) -> String {
            String(format: String(localized: "recurring:removeMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var removeTitle: String { String(localized: "recurring:removeTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var skip: String { String(localized: "recurring:skip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var subtitleLink: String { String(localized: "recurring:subtitleLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var subtitlePre: String { String(localized: "recurring:subtitlePre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "recurring:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Reflect {
        public static var doneBody: String { String(localized: "reflect:doneBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var doneTitle: String { String(localized: "reflect:doneTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var greed: String { String(localized: "reflect:greed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var hint: String { String(localized: "reflect:hint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func left(count: String) -> String {
            String(format: String(localized: "reflect:left", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var need: String { String(localized: "reflect:need", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var skip: String { String(localized: "reflect:skip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "reflect:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var undo: String { String(localized: "reflect:undo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unknown: String { String(localized: "reflect:unknown", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Search {
        public static var allAccounts: String { String(localized: "search:allAccounts", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var clear: String { String(localized: "search:clear", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var filters: String { String(localized: "search:filters", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var fromDate: String { String(localized: "search:fromDate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var maxAmount: String { String(localized: "search:maxAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var minAmount: String { String(localized: "search:minAmount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noMatching: String { String(localized: "search:noMatching", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func resultsCount(count: Int) -> String {
            String(format: String(localized: "search:resultsCount", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var searchEverything: String { String(localized: "search:searchEverything", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "search:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var toDate: String { String(localized: "search:toDate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeAll: String { String(localized: "search:type.all", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeExpense: String { String(localized: "search:type.expense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeIncome: String { String(localized: "search:type.income", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeTransfer: String { String(localized: "search:type.transfer", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Security {
        public static var allowDataAccess: String { String(localized: "security:allowDataAccess", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allowSyncCheck: String { String(localized: "security:allowSyncCheck", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var alreadySetUp: String { String(localized: "security:alreadySetUp", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var checking: String { String(localized: "security:checking", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var codeCopied: String { String(localized: "security:codeCopied", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var confirmPlaceholder: String { String(localized: "security:confirmPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var copyCode: String { String(localized: "security:copyCode", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func grantedUntil(scope: String, time: String) -> String {
            String(format: String(localized: "security:grantedUntil", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), scope, time)
        }
        public static func grantExpires(label: String, time: String) -> String {
            String(format: String(localized: "security:grantExpires", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), label, time)
        }
        public static var grantFailed: String { String(localized: "security:grantFailed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var grantRowContent: String { String(localized: "security:grantRowContent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var grantRowStructural: String { String(localized: "security:grantRowStructural", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var intro: String { String(localized: "security:intro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var invalidRecovery: String { String(localized: "security:invalidRecovery", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var lock: String { String(localized: "security:lock", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var lockedNoteHint: String { String(localized: "security:lockedNoteHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noRecoveryKey: String { String(localized: "security:noRecoveryKey", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var notSetUp: String { String(localized: "security:notSetUp", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var notSignedIn: String { String(localized: "security:notSignedIn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var passphraseLabel: String { String(localized: "security:passphraseLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var passphrasePlaceholder: String { String(localized: "security:passphrasePlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryAck: String { String(localized: "security:recoveryAck", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryCodeLabel: String { String(localized: "security:recoveryCodeLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryHint: String { String(localized: "security:recoveryHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryTitle: String { String(localized: "security:recoveryTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryWarnFive: String { String(localized: "security:recoveryWarnFive", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryWarnForget: String { String(localized: "security:recoveryWarnForget", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryWarnFour: String { String(localized: "security:recoveryWarnFour", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryWarnKeys: String { String(localized: "security:recoveryWarnKeys", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryWarnOne: String { String(localized: "security:recoveryWarnOne", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryWarnSupport: String { String(localized: "security:recoveryWarnSupport", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryWarnThree: String { String(localized: "security:recoveryWarnThree", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryWarnTitle: String { String(localized: "security:recoveryWarnTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryWarnTwo: String { String(localized: "security:recoveryWarnTwo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var recoveryWarnUnrecoverable: String { String(localized: "security:recoveryWarnUnrecoverable", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var revoke: String { String(localized: "security:revoke", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var scopeContent: String { String(localized: "security:scopeContent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var scopeStructural: String { String(localized: "security:scopeStructural", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var setupBusy: String { String(localized: "security:setupBusy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var setupCta: String { String(localized: "security:setupCta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var setupFailed: String { String(localized: "security:setupFailed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var setupMismatch: String { String(localized: "security:setupMismatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var setupNoteBold: String { String(localized: "security:setupNoteBold", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var setupNoteBoth: String { String(localized: "security:setupNoteBoth", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var setupNoteEnd: String { String(localized: "security:setupNoteEnd", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var setupNoteMid: String { String(localized: "security:setupNoteMid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var setupTooShort: String { String(localized: "security:setupTooShort", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var supportBodyHours: String { String(localized: "security:supportBodyHours", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var supportBodyOne: String { String(localized: "security:supportBodyOne", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var supportBodyTwo: String { String(localized: "security:supportBodyTwo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var supportNotConfigured: String { String(localized: "security:supportNotConfigured", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var supportTitle: String { String(localized: "security:supportTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "security:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unlock: String { String(localized: "security:unlock", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unlockBusy: String { String(localized: "security:unlockBusy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unlockedStatus: String { String(localized: "security:unlockedStatus", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unlockForContent: String { String(localized: "security:unlockForContent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unlockIntro: String { String(localized: "security:unlockIntro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var unlockToAuthorize: String { String(localized: "security:unlockToAuthorize", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var usePassphrase: String { String(localized: "security:usePassphrase", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var useRecovery: String { String(localized: "security:useRecovery", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var wrongPassphrase: String { String(localized: "security:wrongPassphrase", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Settings {
        public static var account: String { String(localized: "settings:account", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var allSynced: String { String(localized: "settings:allSynced", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var appearance: String { String(localized: "settings:appearance", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var baseCurrency: String { String(localized: "settings:baseCurrency", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var baseCurrencyDesc: String { String(localized: "settings:baseCurrencyDesc", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cancel: String { String(localized: "settings:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var catsLabels: String { String(localized: "settings:catsLabels", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var catsLabelsDesc: String { String(localized: "settings:catsLabelsDesc", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var connecting: String { String(localized: "settings:connecting", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var contactSupport: String { String(localized: "settings:contactSupport", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var createAccount: String { String(localized: "settings:createAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var createToKeep: String { String(localized: "settings:createToKeep", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dark: String { String(localized: "settings:dark", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteAccount: String { String(localized: "settings:deleteAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteBody: String { String(localized: "settings:deleteBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteErrDefault: String { String(localized: "settings:deleteErrDefault", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteEverything: String { String(localized: "settings:deleteEverything", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteTitle: String { String(localized: "settings:deleteTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleting: String { String(localized: "settings:deleting", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var displayName: String { String(localized: "settings:displayName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var guestBold: String { String(localized: "settings:guestBold", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func guestDelete(count: Int) -> String {
            String(format: String(localized: "settings:guestDelete", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var guestDot: String { String(localized: "settings:guestDot", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var guestPre: String { String(localized: "settings:guestPre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var guestSignoutWarn: String { String(localized: "settings:guestSignoutWarn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var help: String { String(localized: "settings:help", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var helpNote: String { String(localized: "settings:helpNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var hidden: String { String(localized: "settings:hidden", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var hideAmounts: String { String(localized: "settings:hideAmounts", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var hideAmountsDesc: String { String(localized: "settings:hideAmountsDesc", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var importExport: String { String(localized: "settings:importExport", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var importExportBtn: String { String(localized: "settings:importExportBtn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var importExportDesc: String { String(localized: "settings:importExportDesc", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var language: String { String(localized: "settings:language", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var languageSystem: String { String(localized: "settings:languageSystem", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var light: String { String(localized: "settings:light", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var manageCategories: String { String(localized: "settings:manageCategories", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var manageLabels: String { String(localized: "settings:manageLabels", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var privacy: String { String(localized: "settings:privacy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var replayConfirm: String { String(localized: "settings:replayConfirm", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var replayIntro: String { String(localized: "settings:replayIntro", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var replayMsg: String { String(localized: "settings:replayMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var replayTitle: String { String(localized: "settings:replayTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "settings:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var saved: String { String(localized: "settings:saved", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signedInAs: String { String(localized: "settings:signedInAs", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signOut: String { String(localized: "settings:signOut", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signOutAnyway: String { String(localized: "settings:signOutAnyway", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signoutRestore: String { String(localized: "settings:signoutRestore", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var signoutTitle: String { String(localized: "settings:signoutTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func synced(time: String) -> String {
            String(format: String(localized: "settings:synced", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), time)
        }
        public static var syncing: String { String(localized: "settings:syncing", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "settings:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var visible: String { String(localized: "settings:visible", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var yourName: String { String(localized: "settings:yourName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Splits {
        public static var addExpense: String { String(localized: "splits:addExpense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func amountLabel(currency: String) -> String {
            String(format: String(localized: "splits:amountLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), currency)
        }
        public static var cancel: String { String(localized: "splits:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var copied: String { String(localized: "splits:copied", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyBodyLink: String { String(localized: "splits:empty.bodyLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyBodyPost: String { String(localized: "splits:empty.bodyPost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyBodyPre: String { String(localized: "splits:empty.bodyPre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var emptyTitle: String { String(localized: "splits:empty.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var eyebrow: String { String(localized: "splits:eyebrow", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupsAndTrips: String { String(localized: "splits:groupsAndTrips", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var hideLines: String { String(localized: "splits:hideLines", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var insightsAlwaysOwed: String { String(localized: "splits:insights.always_owed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var insightsAlwaysOwes: String { String(localized: "splits:insights.always_owes", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var insightsBiggestLender: String { String(localized: "splits:insights.biggest_lender", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func insightsDays(count: Int) -> String {
            String(format: String(localized: "splits:insights.days", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var insightsFastestSettler: String { String(localized: "splits:insights.fastest_settler", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var insightsFootnote: String { String(localized: "splits:insights.footnote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func insightsGroups(count: Int) -> String {
            String(format: String(localized: "splits:insights.groups", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var insightsOwesYouMost: String { String(localized: "splits:insights.owes_you_most", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var insightsSlowestSettler: String { String(localized: "splits:insights.slowest_settler", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var insightsYouOweMost: String { String(localized: "splits:insights.you_owe_most", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindGroup: String { String(localized: "splits:kind.group", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var kindTrip: String { String(localized: "splits:kind.trip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func membersLine(count: Int, kind: String) -> String {
            String(format: String(localized: "splits:membersLine", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count, kind)
        }
        public static var netPosition: String { String(localized: "splits:netPosition", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newGroupCta: String { String(localized: "splits:newGroupCta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noneMarkSettled: String { String(localized: "splits:noneMarkSettled", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var openGroup: String { String(localized: "splits:openGroup", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func owedInGroup(amount: String) -> String {
            String(format: String(localized: "splits:owedInGroup", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static func oweInGroup(amount: String) -> String {
            String(format: String(localized: "splits:oweInGroup", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var owesYouInline: String { String(localized: "splits:owesYouInline", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var paidFrom: String { String(localized: "splits:paidFrom", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payAnyoneCta: String { String(localized: "splits:payAnyoneCta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var receivedInto: String { String(localized: "splits:receivedInto", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var remind: String { String(localized: "splits:remind", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func remindOwe(name: String, amount: String) -> String {
            String(format: String(localized: "splits:remindOwe", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name, amount)
        }
        public static func remindOwed(name: String, amount: String) -> String {
            String(format: String(localized: "splits:remindOwed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name, amount)
        }
        public static var sectionsFriends: String { String(localized: "splits:sections.friends", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sectionsGroupsAndTrips: String { String(localized: "splits:sections.groupsAndTrips", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sectionsInsights: String { String(localized: "splits:sections.insights", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sectionsOwesYou: String { String(localized: "splits:sections.owesYou", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var sectionsYouOwe: String { String(localized: "splits:sections.youOwe", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settle: String { String(localized: "splits:settle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settledUp: String { String(localized: "splits:settledUp", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settlementTag: String { String(localized: "splits:settlementTag", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settleUp: String { String(localized: "splits:settleUp", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func settleWith(name: String) -> String {
            String(format: String(localized: "splits:settleWith", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var settling: String { String(localized: "splits:settling", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func theyPayYouBack(name: String) -> String {
            String(format: String(localized: "splits:theyPayYouBack", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var totalOwedToYou: String { String(localized: "splits:totalOwedToYou", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var totalYouOwe: String { String(localized: "splits:totalYouOwe", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func viewLines(count: Int) -> String {
            String(format: String(localized: "splits:viewLines", defaultValue: "", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func viewLinesOne(count: String) -> String {
            String(format: String(localized: "splits:viewLines.one", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func viewLinesOther(count: String) -> String {
            String(format: String(localized: "splits:viewLines.other", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var youOweInline: String { String(localized: "splits:youOweInline", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func youPayThemBack(name: String) -> String {
            String(format: String(localized: "splits:youPayThemBack", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var yourBalance: String { String(localized: "splits:yourBalance", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Statements {
        public static var analyze: String { String(localized: "statements:analyze", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var expenses: String { String(localized: "statements:expenses", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var fromDate: String { String(localized: "statements:fromDate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var goPremium: String { String(localized: "statements:goPremium", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var income: String { String(localized: "statements:income", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var netForPeriod: String { String(localized: "statements:netForPeriod", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noTransactions: String { String(localized: "statements:noTransactions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var premiumBody: String { String(localized: "statements:premiumBody", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var premiumTitle: String { String(localized: "statements:premiumTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var print: String { String(localized: "statements:print", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var share: String { String(localized: "statements:share", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var statementName: String { String(localized: "statements:statementName", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "statements:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var toDate: String { String(localized: "statements:toDate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var today: String { String(localized: "statements:today", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var transactions: String { String(localized: "statements:transactions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var yesterday: String { String(localized: "statements:yesterday", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum StatementsAnalyze {
        public static var accountToReconcile: String { String(localized: "statementsAnalyze:accountToReconcile", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addAsRecurring: String { String(localized: "statementsAnalyze:addAsRecurring", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var added: String { String(localized: "statementsAnalyze:added", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var bank: String { String(localized: "statementsAnalyze:bank", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cadenceMonthly: String { String(localized: "statementsAnalyze:cadence.monthly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cadenceWeekly: String { String(localized: "statementsAnalyze:cadence.weekly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var cadenceYearly: String { String(localized: "statementsAnalyze:cadence.yearly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var card: String { String(localized: "statementsAnalyze:card", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var categorising: String { String(localized: "statementsAnalyze:categorising", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var chooseFile: String { String(localized: "statementsAnalyze:chooseFile", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var chooseFileCsvOnly: String { String(localized: "statementsAnalyze:chooseFileCsvOnly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var chooseLater: String { String(localized: "statementsAnalyze:chooseLater", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var closingBalance: String { String(localized: "statementsAnalyze:closingBalance", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var dailySpend: String { String(localized: "statementsAnalyze:dailySpend", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var importedDone: String { String(localized: "statementsAnalyze:importedDone", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func importMissing(count: String, account: String) -> String {
            String(format: String(localized: "statementsAnalyze:importMissing", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count, account)
        }
        public static var introBold: String { String(localized: "statementsAnalyze:introBold", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var introLink: String { String(localized: "statementsAnalyze:introLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var introMid: String { String(localized: "statementsAnalyze:introMid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var introPost: String { String(localized: "statementsAnalyze:introPost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var introPre: String { String(localized: "statementsAnalyze:introPre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var looksRecurring: String { String(localized: "statementsAnalyze:looksRecurring", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var matchedLabel: String { String(localized: "statementsAnalyze:matchedLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var minimumDue: String { String(localized: "statementsAnalyze:minimumDue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var missingLabel: String { String(localized: "statementsAnalyze:missingLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var moneyIn: String { String(localized: "statementsAnalyze:moneyIn", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var moneyOut: String { String(localized: "statementsAnalyze:moneyOut", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var net: String { String(localized: "statementsAnalyze:net", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newStatement: String { String(localized: "statementsAnalyze:newStatement", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noSpends: String { String(localized: "statementsAnalyze:noSpends", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var onlyPlatformLabel: String { String(localized: "statementsAnalyze:onlyPlatformLabel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var outliersTitle: String { String(localized: "statementsAnalyze:outliersTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var parsing: String { String(localized: "statementsAnalyze:parsing", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var payBy: String { String(localized: "statementsAnalyze:payBy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pdfCancel: String { String(localized: "statementsAnalyze:pdfCancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pdfPassword: String { String(localized: "statementsAnalyze:pdfPassword", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pdfUnavailable: String { String(localized: "statementsAnalyze:pdfUnavailable", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pdfUnlock: String { String(localized: "statementsAnalyze:pdfUnlock", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pickAccountReconcile: String { String(localized: "statementsAnalyze:pickAccountReconcile", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var readFail: String { String(localized: "statementsAnalyze:readFail", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var readingPdf: String { String(localized: "statementsAnalyze:readingPdf", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reconcileTitle: String { String(localized: "statementsAnalyze:reconcileTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func recurringMeta(amount: String, cadence: String, count: String) -> String {
            String(format: String(localized: "statementsAnalyze:recurringMeta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount, cadence, count)
        }
        public static func showAll(count: String) -> String {
            String(format: String(localized: "statementsAnalyze:showAll", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var showLess: String { String(localized: "statementsAnalyze:showLess", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var statementType: String { String(localized: "statementsAnalyze:statementType", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tipBold: String { String(localized: "statementsAnalyze:tipBold", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tipPost: String { String(localized: "statementsAnalyze:tipPost", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var tipPre: String { String(localized: "statementsAnalyze:tipPre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "statementsAnalyze:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var totalDue: String { String(localized: "statementsAnalyze:totalDue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func transactions(count: String) -> String {
            String(format: String(localized: "statementsAnalyze:transactions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static func transactionsTitle(count: String) -> String {
            String(format: String(localized: "statementsAnalyze:transactionsTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), count)
        }
        public static var whereItWent: String { String(localized: "statementsAnalyze:whereItWent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Sync {
        public static var offline: String { String(localized: "sync:offline", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var reportIssue: String { String(localized: "sync:reportIssue", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var trouble: String { String(localized: "sync:trouble", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Templates {
        public static var account: String { String(localized: "templates:account", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func actions(name: String) -> String {
            String(format: String(localized: "templates:actions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static func amountPlaceholder(base: String) -> String {
            String(format: String(localized: "templates:amountPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), base)
        }
        public static var cancel: String { String(localized: "templates:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var chooseAtUse: String { String(localized: "templates:chooseAtUse", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var create: String { String(localized: "templates:create", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var delete: String { String(localized: "templates:delete", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "templates:deleteMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var deleteTitle: String { String(localized: "templates:deleteTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var descriptionPlaceholder: String { String(localized: "templates:descriptionPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var edit: String { String(localized: "templates:edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var editTitle: String { String(localized: "templates:editTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func freeUsed(used: String, limit: String) -> String {
            String(format: String(localized: "templates:freeUsed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), used, limit)
        }
        public static var goPremium: String { String(localized: "templates:goPremium", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var introLink: String { String(localized: "templates:introLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var introPre: String { String(localized: "templates:introPre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func limitMsg(limit: String) -> String {
            String(format: String(localized: "templates:limitMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), limit)
        }
        public static var limitTitle: String { String(localized: "templates:limitTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var namePlaceholder: String { String(localized: "templates:namePlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newTemplate: String { String(localized: "templates:newTemplate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newTitle: String { String(localized: "templates:newTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noTemplates: String { String(localized: "templates:noTemplates", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var save: String { String(localized: "templates:save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var split: String { String(localized: "templates:split", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "templates:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeExpense: String { String(localized: "templates:type.expense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeIncome: String { String(localized: "templates:type.income", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var use: String { String(localized: "templates:use", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Transactions {
        public static var account: String { String(localized: "transactions:account", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var add: String { String(localized: "transactions:add", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addItemSplit: String { String(localized: "transactions:addItemSplit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var addTitle: String { String(localized: "transactions:addTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var amount: String { String(localized: "transactions:amount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func amountCurrency(currency: String) -> String {
            String(format: String(localized: "transactions:amountCurrency", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), currency)
        }
        public static func amountReceived(currency: String) -> String {
            String(format: String(localized: "transactions:amountReceived", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), currency)
        }
        public static var amountWithItems: String { String(localized: "transactions:amountWithItems", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditAccountId: String { String(localized: "transactions:audit.account_id", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditAmount: String { String(localized: "transactions:audit.amount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditCategoryId: String { String(localized: "transactions:audit.category_id", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditDescription: String { String(localized: "transactions:audit.description", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditMerchant: String { String(localized: "transactions:audit.merchant", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditNote: String { String(localized: "transactions:audit.note", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditOccurredAt: String { String(localized: "transactions:audit.occurred_at", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditPaymentMethodId: String { String(localized: "transactions:audit.payment_method_id", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditToAccountId: String { String(localized: "transactions:audit.to_account_id", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditToAmount: String { String(localized: "transactions:audit.to_amount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditType: String { String(localized: "transactions:audit.type", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditActionDelete: String { String(localized: "transactions:auditAction.delete", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var auditActionUpdate: String { String(localized: "transactions:auditAction.update", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var autoCategorised: String { String(localized: "transactions:autoCategorised", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func autoSplitWith(name: String) -> String {
            String(format: String(localized: "transactions:autoSplitWith", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var cancel: String { String(localized: "transactions:cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var category: String { String(localized: "transactions:category", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var chooseGroup: String { String(localized: "transactions:chooseGroup", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var countsInBudget: String { String(localized: "transactions:countsInBudget", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var createAccountFirst: String { String(localized: "transactions:createAccountFirst", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var date: String { String(localized: "transactions:date", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var defaultExpense: String { String(localized: "transactions:defaultExpense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var defaultIncome: String { String(localized: "transactions:defaultIncome", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var defaultTransfer: String { String(localized: "transactions:defaultTransfer", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var delete: String { String(localized: "transactions:delete", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteConfirmMsg: String { String(localized: "transactions:deleteConfirmMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var deleteConfirmTitle: String { String(localized: "transactions:deleteConfirmTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var editHistory: String { String(localized: "transactions:editHistory", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var editTitle: String { String(localized: "transactions:editTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var extraNotes: String { String(localized: "transactions:extraNotes", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var filterAll: String { String(localized: "transactions:filter.all", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var filterExpense: String { String(localized: "transactions:filter.expense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var filterIncome: String { String(localized: "transactions:filter.income", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var filterTransfer: String { String(localized: "transactions:filter.transfer", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var findingCategory: String { String(localized: "transactions:findingCategory", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var fromAccount: String { String(localized: "transactions:fromAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var groupTrip: String { String(localized: "transactions:groupTrip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var investmentBlocked: String { String(localized: "transactions:investmentBlocked", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var investmentTransferOnly: String { String(localized: "transactions:investmentTransferOnly", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func item(n: String) -> String {
            String(format: String(localized: "transactions:item", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), n)
        }
        public static var labels: String { String(localized: "transactions:labels", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var labelsOptional: String { String(localized: "transactions:labelsOptional", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var loading: String { String(localized: "transactions:loading", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func memberPaid(name: String) -> String {
            String(format: String(localized: "transactions:memberPaid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var minorUpdate: String { String(localized: "transactions:minorUpdate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var modeEqual: String { String(localized: "transactions:mode.equal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var modeExact: String { String(localized: "transactions:mode.exact", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var modePercent: String { String(localized: "transactions:mode.percent", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var multiplePaid: String { String(localized: "transactions:multiplePaid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var newAccountCta: String { String(localized: "transactions:newAccountCta", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noEdits: String { String(localized: "transactions:noEdits", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noMatching: String { String(localized: "transactions:noMatching", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var note: String { String(localized: "transactions:note", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var noteOptional: String { String(localized: "transactions:noteOptional", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var onlyYou: String { String(localized: "transactions:onlyYou", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func onlyYourPayment(account: String) -> String {
            String(format: String(localized: "transactions:onlyYourPayment", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), account)
        }
        public static var optionalNote: String { String(localized: "transactions:optionalNote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func othersOweYou(amount: String) -> String {
            String(format: String(localized: "transactions:othersOweYou", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static var paidForSomeone: String { String(localized: "transactions:paidForSomeone", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var paidForSomeoneHint: String { String(localized: "transactions:paidForSomeoneHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var paidForSomeoneNoOne: String { String(localized: "transactions:paidForSomeoneNoOne", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var paidForSomeonePick: String { String(localized: "transactions:paidForSomeonePick", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func paidMatch(sum: String, total: String) -> String {
            String(format: String(localized: "transactions:paidMatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), sum, total)
        }
        public static func paidMismatch(sum: String, total: String) -> String {
            String(format: String(localized: "transactions:paidMismatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), sum, total)
        }
        public static var paymentMethod: String { String(localized: "transactions:paymentMethod", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func percentMatch(pct: String) -> String {
            String(format: String(localized: "transactions:percentMatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), pct)
        }
        public static func percentMismatch(pct: String) -> String {
            String(format: String(localized: "transactions:percentMismatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), pct)
        }
        public static var pickGroupLink: String { String(localized: "transactions:pickGroupLink", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pickGroupPre: String { String(localized: "transactions:pickGroupPre", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pickTwo: String { String(localized: "transactions:pickTwo", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var remove: String { String(localized: "transactions:remove", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var saveAsTemplate: String { String(localized: "transactions:saveAsTemplate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var saveChanges: String { String(localized: "transactions:saveChanges", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var saveChangesError: String { String(localized: "transactions:saveChangesError", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var savedAsTemplate: String { String(localized: "transactions:savedAsTemplate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var saveError: String { String(localized: "transactions:saveError", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func saveWithTotal(total: String) -> String {
            String(format: String(localized: "transactions:saveWithTotal", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), total)
        }
        public static var saving: String { String(localized: "transactions:saving", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var scannedChip: String { String(localized: "transactions:scannedChip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var searchCategory: String { String(localized: "transactions:searchCategory", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var searchPlaceholder: String { String(localized: "transactions:searchPlaceholder", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func sharesMatch(sum: String, total: String) -> String {
            String(format: String(localized: "transactions:sharesMatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), sum, total)
        }
        public static func sharesMismatch(sum: String, total: String) -> String {
            String(format: String(localized: "transactions:sharesMismatch", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), sum, total)
        }
        public static var someone: String { String(localized: "transactions:someone", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitBannerFootnote: String { String(localized: "transactions:splitBanner.footnote", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitBannerOpenGroup: String { String(localized: "transactions:splitBanner.openGroup", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func splitBannerOpenNamed(name: String) -> String {
            String(format: String(localized: "transactions:splitBanner.openNamed", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), name)
        }
        public static var splitBannerOwedToYou: String { String(localized: "transactions:splitBanner.owedToYou", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func splitBannerParticipantLine(share: String, paid: String) -> String {
            String(format: String(localized: "transactions:splitBanner.participantLine", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), share, paid)
        }
        public static var splitBannerParticipants: String { String(localized: "transactions:splitBanner.participants", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitBannerTitle: String { String(localized: "transactions:splitBanner.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitBannerTotalBill: String { String(localized: "transactions:splitBanner.totalBill", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitBannerYouOwe: String { String(localized: "transactions:splitBanner.youOwe", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitBannerYouPaid: String { String(localized: "transactions:splitBanner.youPaid", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitBannerYourShare: String { String(localized: "transactions:splitBanner.yourShare", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitBetween: String { String(localized: "transactions:splitBetween", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitChip: String { String(localized: "transactions:splitChip", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var splitExpense: String { String(localized: "transactions:splitExpense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var startFromTemplate: String { String(localized: "transactions:startFromTemplate", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func templateLimitMsg(limit: String) -> String {
            String(format: String(localized: "transactions:templateLimitMsg", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), limit)
        }
        public static var templateLimitTitle: String { String(localized: "transactions:templateLimitTitle", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var templateNamePrompt: String { String(localized: "transactions:templateNamePrompt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var title: String { String(localized: "transactions:title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var toAccount: String { String(localized: "transactions:toAccount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var txOptions: String { String(localized: "transactions:txOptions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeExpense: String { String(localized: "transactions:type.expense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeIncome: String { String(localized: "transactions:type.income", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var typeTransfer: String { String(localized: "transactions:type.transfer", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var uncategorised: String { String(localized: "transactions:uncategorised", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var viewHistory: String { String(localized: "transactions:viewHistory", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var whatFor: String { String(localized: "transactions:whatFor", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var you: String { String(localized: "transactions:you", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func youllOwe(amount: String) -> String {
            String(format: String(localized: "transactions:youllOwe", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), amount)
        }
        public static func youPaidFrom(total: String, account: String) -> String {
            String(format: String(localized: "transactions:youPaidFrom", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), total, account)
        }
        public static var yourShare: String { String(localized: "transactions:yourShare", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }

    public enum Translation {
        public static var accountTypeCash: String { String(localized: "translation:accountType.cash", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var accountTypeCreditCard: String { String(localized: "translation:accountType.credit_card", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var accountTypeCurrent: String { String(localized: "translation:accountType.current", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var accountTypeMutualFunds: String { String(localized: "translation:accountType.mutual_funds", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var accountTypeSavings: String { String(localized: "translation:accountType.savings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var accountTypeStocks: String { String(localized: "translation:accountType.stocks", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var appName: String { String(localized: "translation:app.name", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonAdd: String { String(localized: "translation:common.add", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonAdding: String { String(localized: "translation:common.adding", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonBack: String { String(localized: "translation:common.back", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonCancel: String { String(localized: "translation:common.cancel", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonClear: String { String(localized: "translation:common.clear", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonClose: String { String(localized: "translation:common.close", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonDelete: String { String(localized: "translation:common.delete", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonDone: String { String(localized: "translation:common.done", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonEdit: String { String(localized: "translation:common.edit", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonRemove: String { String(localized: "translation:common.remove", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonSave: String { String(localized: "translation:common.save", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonSaveChanges: String { String(localized: "translation:common.saveChanges", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonSaving: String { String(localized: "translation:common.saving", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var commonSettings: String { String(localized: "translation:common.settings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var fabAdd: String { String(localized: "translation:fab.add", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var fabAddTransaction: String { String(localized: "translation:fab.addTransaction", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var fabClose: String { String(localized: "translation:fab.close", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var fabScanReceipt: String { String(localized: "translation:fab.scanReceipt", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navAccounts: String { String(localized: "translation:nav.accounts", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navAssistant: String { String(localized: "translation:nav.assistant", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navBudgets: String { String(localized: "translation:nav.budgets", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navCards: String { String(localized: "translation:nav.cards", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navCustomize: String { String(localized: "translation:nav.customize", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func navCustomizeHint(n: String) -> String {
            String(format: String(localized: "translation:nav.customizeHint", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), n)
        }
        public static var navFriends: String { String(localized: "translation:nav.friends", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navGoals: String { String(localized: "translation:nav.goals", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navHelp: String { String(localized: "translation:nav.help", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navHome: String { String(localized: "translation:nav.home", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navInsights: String { String(localized: "translation:nav.insights", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navInvestments: String { String(localized: "translation:nav.investments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navLoans: String { String(localized: "translation:nav.loans", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navMore: String { String(localized: "translation:nav.more", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navNotifications: String { String(localized: "translation:nav.notifications", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navRecurring: String { String(localized: "translation:nav.recurring", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navReflect: String { String(localized: "translation:nav.reflect", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navSearch: String { String(localized: "translation:nav.search", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navSettings: String { String(localized: "translation:nav.settings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navStatements: String { String(localized: "translation:nav.statements", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navSubscriptions: String { String(localized: "translation:nav.subscriptions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var navTransactions: String { String(localized: "translation:nav.transactions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var netWorthAvailable: String { String(localized: "translation:netWorth.available", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var netWorthTitle: String { String(localized: "translation:netWorth.title", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var netWorthWithBlocked: String { String(localized: "translation:netWorth.withBlocked", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var onboardingGetStarted: String { String(localized: "translation:onboarding.getStarted", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static func onboardingGuestBanner(days: String) -> String {
            String(format: String(localized: "translation:onboarding.guestBanner", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale), days)
        }
        public static var pagesAccounts: String { String(localized: "translation:pages.accounts", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesBudgets: String { String(localized: "translation:pages.budgets", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesCards: String { String(localized: "translation:pages.cards", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesDashboard: String { String(localized: "translation:pages.dashboard", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesGoals: String { String(localized: "translation:pages.goals", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesInsights: String { String(localized: "translation:pages.insights", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesInvestments: String { String(localized: "translation:pages.investments", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesLoans: String { String(localized: "translation:pages.loans", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesSearch: String { String(localized: "translation:pages.search", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesSettings: String { String(localized: "translation:pages.settings", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesStatements: String { String(localized: "translation:pages.statements", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesSubscriptions: String { String(localized: "translation:pages.subscriptions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var pagesTransactions: String { String(localized: "translation:pages.transactions", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsAccount: String { String(localized: "translation:settings.account", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsAppearance: String { String(localized: "translation:settings.appearance", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsBaseCurrency: String { String(localized: "translation:settings.baseCurrency", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsDark: String { String(localized: "translation:settings.dark", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsHelp: String { String(localized: "translation:settings.help", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsHideAmounts: String { String(localized: "translation:settings.hideAmounts", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsLanguage: String { String(localized: "translation:settings.language", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsLight: String { String(localized: "translation:settings.light", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsPlan: String { String(localized: "translation:settings.plan", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var settingsPrivacy: String { String(localized: "translation:settings.privacy", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var transactionAddItem: String { String(localized: "translation:transaction.addItem", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var transactionAmount: String { String(localized: "translation:transaction.amount", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var transactionCategory: String { String(localized: "translation:transaction.category", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var transactionExpense: String { String(localized: "translation:transaction.expense", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var transactionIncome: String { String(localized: "translation:transaction.income", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var transactionLabel: String { String(localized: "translation:transaction.label", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
        public static var transactionTransfer: String { String(localized: "translation:transaction.transfer", table: "Localizable", bundle: SanvyaLocale.bundle, locale: SanvyaLocale.locale) }
    }
}
